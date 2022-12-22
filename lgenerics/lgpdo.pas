{****************************************************************************
*                                                                           *
*   This file is part of the LGenerics package.                             *
*   Plain Data Objects and serialization.                                   *
*                                                                           *
*   Copyright(c) 2022 A.Koverdyaev(avk)                                     *
*                                                                           *
*   This code is free software; you can redistribute it and/or modify it    *
*   under the terms of the Apache License, Version 2.0;                     *
*   You may obtain a copy of the License at                                 *
*     http://www.apache.org/licenses/LICENSE-2.0.                           *
*                                                                           *
*  Unless required by applicable law or agreed to in writing, software      *
*  distributed under the License is distributed on an "AS IS" BASIS,        *
*  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied. *
*  See the License for the specific language governing permissions and      *
*  limitations under the License.                                           *
*                                                                           *
*****************************************************************************}
unit lgPdo;

{$MODE OBJFPC}{$H+}{$MODESWITCH ADVANCEDRECORDS}

interface

uses
  Classes, SysUtils, TypInfo, lgJson;

{ PDO - Plain Data Object, currently supported:
   - numeric, boolean or string types, some limited support of Variant;
   - regular records, it is possible to register a list of field names or a custom callback;
   - classes, using published properties or by registering a custom callback;
   - object, only by registering a serialization callback;
   - static arrays of PDO(only one-dimensional, multidimensional arrays are written as one-dimensional);
   - dynamic arrays of PDO;
   - variant arrays(currently only one-dimensional);
}

{ converts PDO to JSON; unsupported data types will be written as "unknown data"(see UNKNOWN_ALIAS);
  fields of unregistered records will be named as "field1, field2, ..."(see FIELD_ALIAS) }
  generic function PdoToJson<T>(const aValue: T): string;
  function PdoToJson(aTypeInfo: PTypeInfo; const aValue): string;
  { the type being registered must be a record; associates the field names aFieldNames with
    the record fields by their indexes; to exclude a field from serialization, it is sufficient
    to specify its name as an empty string; to avoid name mapping errors, it makes sense to use
    the $OPTIMIZATION NOORDERFIELDS directive in the record declaration; returns True on
    successful registration }
  function RegisterRecordFields(aTypeInfo: PTypeInfo; const aFieldNames: TStringArray): Boolean;
  function RegisteredRecordFields(aTypeInfo: PTypeInfo; out aFieldNames: TStringArray): Boolean;
  function UnRegisterPdo(aTypeInfo: PTypeInfo): Boolean;

type
  TJsonStrWriter   = lgJson.TJsonStrWriter;
  TClassJsonProc   = procedure(o: TObject; aWriter: TJsonStrWriter);
  TPointerJsonProc = procedure(r: Pointer; aWriter: TJsonStrWriter);

{ associates a custom JSON serialization procedure with a type; the type must be a class, only
  one procedure can be associated with each class; returns True if registration is successful }
  function RegisterClassJsonProc(aTypeInfo: PTypeInfo; aProc: TClassJsonProc): Boolean;
{ associates a custom JSON serialization procedure with a type; the type must be a record, only one
  procedure can be associated with each record type; returns True if registration is successful }
  function RegisterRecordJsonProc(aTypeInfo: PTypeInfo; aProc: TPointerJsonProc): Boolean;
{ associates a custom JSON serialization procedure with a type; the type must be an object, only one
  procedure can be associated with each object type; returns True if registration is successful }
  function RegisterObjectJsonProc(aTypeInfo: PTypeInfo; aProc: TPointerJsonProc): Boolean;
  function RegisteredPdoProc(aTypeInfo: Pointer): Boolean;

const
  UNKNOWN_ALIAS = 'unknown data';
  FIELD_ALIAS   = 'field';
  SUPPORT_KINDS = [
    tkInteger, tkChar, tkFloat, tkSString, tkLString, tkAString, tkWString, tkVariant, tkArray,
    tkRecord, tkClass, tkObject, tkWChar, tkBool, tkInt64, tkQWord, tkDynArray, tkUString, tkUChar];

implementation
{$B-}{$COPERATORS ON}{$POINTERMATH ON}
uses
  Math, Variants, RttiUtils, lgUtils, lgHashMap;

type
  TRecField = record
    Name: string;
    Offset: Integer;
    Info: PTypeInfo;
  end;

  TRecFieldMap = array of TRecField;
  TEntryKind   = (ekRecFieldMap, ekClassJsonProc, ekRecJsonProc, ekObjJsonProc);

  TPdoCacheEntry = record
    FieldMap: TRecFieldMap;
    CustomProc: Pointer;
    Kind: TEntryKind;
    constructor Create(const aFieldMap: TRecFieldMap);
    constructor CreateClass(aProc: TClassJsonProc);
    constructor CreateRec(aProc: TPointerJsonProc);
    constructor CreateObj(aProc: TPointerJsonProc);
  end;
  PPdoCacheEntry = ^TPdoCacheEntry;

  TPdoCacheType = specialize TGLiteChainHashMap<Pointer, TPdoCacheEntry, Pointer>;
  TPdoCache     = TPdoCacheType.TMap;

constructor TPdoCacheEntry.Create(const aFieldMap: TRecFieldMap);
begin
  FieldMap := aFieldMap;
  CustomProc := nil;
  Kind := ekRecFieldMap;
end;

constructor TPdoCacheEntry.CreateClass(aProc: TClassJsonProc);
begin
  FieldMap := nil;
  CustomProc := aProc;
  Kind := ekClassJsonProc;
end;

constructor TPdoCacheEntry.CreateRec(aProc: TPointerJsonProc);
begin
  FieldMap := nil;
  CustomProc := aProc;
  Kind := ekRecJsonProc;
end;

constructor TPdoCacheEntry.CreateObj(aProc: TPointerJsonProc);
begin
  FieldMap := nil;
  CustomProc := aProc;
  Kind := ekObjJsonProc;
end;

var
  GlobLock: TRtlCriticalSection;
  PdoCache: TPdoCache;

function AddPdo(aTypeInfo: Pointer; const aFieldNames: TStringArray): Boolean;
var
  pTypData: PTypeData;
  pManField: PManagedField;
  FieldMap: TRecFieldMap;
  I, Count: Integer;
begin
  Result := False;
  if PdoCache.Contains(aTypeInfo) then exit(False);
  try
    pTypData := GetTypeData(aTypeInfo);
    Count := pTypData^.TotalFieldCount;
    System.SetLength(FieldMap, Count);
    pManField := PManagedField(
      AlignTypeData(PByte(@pTypData^.TotalFieldCount) + SizeOf(pTypData^.TotalFieldCount)));
    for I := 0 to Math.Min(Pred(Count), System.High(aFieldNames)) do
      begin
        FieldMap[I].Name := aFieldNames[I];
        FieldMap[I].Offset := pManField^.FldOffset;
        FieldMap[I].Info := pManField^.TypeRef;
        Inc(pManField);
      end;
  except
    exit(False);
  end;
  EnterCriticalSection(GlobLock);
  try
    Result := PdoCache.Add(aTypeInfo, TPdoCacheEntry.Create(FieldMap));
  finally
    LeaveCriticalSection(GlobLock);
  end;
end;

function GetPdoEntry(aTypeInfo: Pointer; out e: TPdoCacheEntry): Boolean;
begin
  EnterCriticalSection(GlobLock);
  try
    Result := PdoCache.TryGetValue(aTypeInfo, e);
  finally
    LeaveCriticalSection(GlobLock);
  end;
end;

function RegisterRecordFields(aTypeInfo: PTypeInfo; const aFieldNames: TStringArray): Boolean;
begin
  if aTypeInfo = nil then exit(False);
  if aTypeInfo^.Kind <> tkRecord then exit(False);
  Result := AddPdo(aTypeInfo, aFieldNames);
end;

function RegisteredRecordFields(aTypeInfo: PTypeInfo; out aFieldNames: TStringArray): Boolean;
var
  pe: PPdoCacheEntry;
  FieldMap: TRecFieldMap;
  I: Integer;
begin
  aFieldNames := nil;
  pe := nil;
  FieldMap := nil;
  Result := False;
  EnterCriticalSection(GlobLock);
  try
    if not PdoCache.TryGetMutValue(aTypeInfo, pe) then exit;
    if pe^.Kind <> ekRecFieldMap then exit;
    FieldMap := pe^.FieldMap;
  finally
    LeaveCriticalSection(GlobLock);
  end;
  if FieldMap <> nil then
    begin
      System.SetLength(aFieldNames, System.Length(FieldMap));
      for I := 0 to System.High(FieldMap) do
        aFieldNames[I] := FieldMap[I].Name;
      Result := True;
    end;
end;

function UnRegisterPdo(aTypeInfo: PTypeInfo): Boolean;
begin
  EnterCriticalSection(GlobLock);
  try
    Result := PdoCache.Remove(aTypeInfo);
  finally
    LeaveCriticalSection(GlobLock);
  end;
end;

function RegisterClassJsonProc(aTypeInfo: PTypeInfo; aProc: TClassJsonProc): Boolean;
begin
  if aTypeInfo = nil then exit(False);
  if aTypeInfo^.Kind <> tkClass then exit(False);
  if aProc = nil then exit(False);
  EnterCriticalSection(GlobLock);
  try
    Result := PdoCache.Add(aTypeInfo, TPdoCacheEntry.CreateClass(aProc));
  finally
    LeaveCriticalSection(GlobLock);
  end;
end;

function RegisterRecordJsonProc(aTypeInfo: PTypeInfo; aProc: TPointerJsonProc): Boolean;
begin
  if aTypeInfo = nil then exit(False);
  if aTypeInfo^.Kind <> tkRecord then exit(False);
  if aProc = nil then exit(False);
  EnterCriticalSection(GlobLock);
  try
    Result := PdoCache.Add(aTypeInfo, TPdoCacheEntry.CreateRec(aProc));
  finally
    LeaveCriticalSection(GlobLock);
  end;
end;

function RegisterObjectJsonProc(aTypeInfo: PTypeInfo; aProc: TPointerJsonProc): Boolean;
begin
  if aTypeInfo = nil then exit(False);
  if aTypeInfo^.Kind <> tkObject then exit(False);
  if aProc = nil then exit(False);
  EnterCriticalSection(GlobLock);
  try
    Result := PdoCache.Add(aTypeInfo, TPdoCacheEntry.CreateObj(aProc));
  finally
    LeaveCriticalSection(GlobLock);
  end;
end;

function RegisteredPdoProc(aTypeInfo: Pointer): Boolean;
var
  pe: PPdoCacheEntry;
begin
  pe := nil;
  EnterCriticalSection(GlobLock);
  try
    if not PdoCache.TryGetMutValue(aTypeInfo, pe) then exit(False);
    Result := pe^.Kind <> ekRecFieldMap;
  finally
    LeaveCriticalSection(GlobLock);
  end;
end;

generic function PdoToJson<T>(const aValue: T): string;
begin
  Result := PdoToJson(TypeInfo(T), aValue);
end;

function PdoToJson(aTypeInfo: PTypeInfo; const aValue): string;
var
  Writer: TJsonStrWriter;
  procedure WriteInteger(aTypData: PTypeData; aData: Pointer); inline;
  var
    d: Double;
  begin
    case aTypData^.OrdType of
      otSByte:  d := PShortInt(aData)^;
      otUByte:  d := PByte(aData)^;
      otSWord:  d := PSmallInt(aData)^;
      otUWord:  d := PWord(aData)^;
      otSLong:  d := PLongInt(aData)^;
      otULong:  d := PDword(aData)^;
      otSQWord: d := PInt64(aData)^;
      otUQWord: d := PQWord(aData)^;
    end;
    Writer.Add(d);
  end;
  procedure WriteFloat(aTypData: PTypeData; aData: Pointer); inline;
  var
    d: Double;
  begin
    case aTypData^.FloatType of
      ftSingle:   d := PSingle(aData)^;
      ftDouble:   d := PDouble(aData)^;
      ftExtended: d := PExtended(aData)^;
      ftComp:     d := PComp(aData)^;
      ftCurr:     d := PCurrency(aData)^;
    end;
    Writer.Add(d);
  end;
  procedure WriteBool(aTypData: PTypeData; aData: Pointer); inline;
  var
    IsTrue: Boolean;
  begin
    case aTypData^.OrdType of
      otSByte:  IsTrue := PShortInt(aData)^ > 0;
      otUByte:  IsTrue := PByte(aData)^ > 0;
      otSWord:  IsTrue := PSmallInt(aData)^ > 0;
      otUWord:  IsTrue := PWord(aData)^ > 0;
      otSLong:  IsTrue := PLongInt(aData)^ > 0;
      otULong:  IsTrue := PDword(aData)^ > 0;
      otSQWord: IsTrue := PInt64(aData)^ > 0;
      otUQWord: IsTrue := PQWord(aData)^ > 0;
    end;
    if IsTrue then
      Writer.AddTrue
    else
      Writer.AddFalse;
  end;
  procedure WriteField(aTypeInfo: PTypeInfo; aData: Pointer); forward;
  procedure WriteRegRecord(aData: Pointer; const aFieldMap: TRecFieldMap);
  var
    I: Integer;
  begin
    Writer.BeginObject;
    for I := 0 to System.High(aFieldMap) do
      if aFieldMap[I].Name <> '' then
        begin
          Writer.AddName(aFieldMap[I].Name);
          WriteField(aFieldMap[I].Info, PByte(aData) + aFieldMap[I].Offset);
        end;
    Writer.EndObject;
  end;
  procedure WriteUnregRecord(aTypeInfo: PTypeInfo; aData: Pointer);
  var
    pTypData: PTypeData;
    pManField: PManagedField;
    I: Integer;
  begin
    pTypData := GetTypeData(aTypeInfo);
    pManField := PManagedField(
      AlignTypeData(PByte(@pTypData^.TotalFieldCount) + SizeOf(pTypData^.TotalFieldCount)));
    Writer.BeginObject;
    for I := 0 to Pred(pTypData^.TotalFieldCount) do
      begin
        Writer.AddName(FIELD_ALIAS + Succ(I).ToString);
        WriteField(pManField^.TypeRef, PByte(aData) + pManField^.FldOffset);
        Inc(pManField);
      end;
    Writer.EndObject;
  end;
  procedure WriteRecord(aTypeInfo: PTypeInfo; aData: Pointer); inline;
  var
    e: TPdoCacheEntry;
  begin
    if GetPdoEntry(aTypeInfo, e) then
      case e.Kind of
        ekRecFieldMap:
          begin
            WriteRegRecord(aData, e.FieldMap);
            exit;
          end;
        ekRecJsonProc:
          begin
            TPointerJsonProc(e.CustomProc)(aData, Writer);
            exit
          end;
      else
      end;
    WriteUnregRecord(aTypeInfo, aData);
  end;
  procedure WriteArray(aTypeInfo: PTypeInfo; aData: Pointer);
  var
    e: TPdoCacheEntry;
    pTypData: PTypeData;
    ElSize: SizeUInt;
    ElType: PTypeInfo;
    Arr: PByte;
    I, Count: SizeInt;
  begin
    pTypData := GetTypeData(aTypeInfo);
    ElType := pTypData^.ArrayData.ElType;
    Count := pTypData^.ArrayData.ElCount;
    ElSize := pTypData^.ArrayData.Size div Count;
    Arr := aData;
    Writer.BeginArray;
    try
      if GetPdoEntry(ElType, e) then
        begin
          case e.Kind of
            ekRecFieldMap:
              for I := 0 to Pred(Count) do
                begin
                  WriteRegRecord(Arr, e.FieldMap);
                  Arr += ElSize;
                end;
            ekRecJsonProc:
              for I := 0 to Pred(Count) do
                begin
                  TPointerJsonProc(e.CustomProc)(Arr, Writer);
                  Arr += ElSize;
                end;
          else
          end;
          exit;
        end;
      for I := 0 to Pred(Count) do
        begin
          WriteField(ElType, Arr);
          Arr += ElSize;
        end;
    finally
      Writer.EndArray;
    end;
  end;
  procedure WriteDynArray(aTypeInfo: PTypeInfo; aData: Pointer);
  var
    e: TPdoCacheEntry;
    pTypData: PTypeData;
    ElSize: SizeUInt;
    ElType: PTypeInfo;
    Arr: PByte;
    I: SizeInt;
  begin
    pTypData := GetTypeData(aTypeInfo);
    ElSize := pTypData^.elSize;
    ElType := pTypData^.ElType2;
    Arr := Pointer(aData^);
    Writer.BeginArray;
    try
      if GetPdoEntry(ElType, e) then
        begin
          case e.Kind of
            ekRecFieldMap:
              for I := 0 to Pred(DynArraySize(Arr)) do
                begin
                  WriteRegRecord(Arr, e.FieldMap);
                  Arr += ElSize;
                end;
            ekRecJsonProc:
              for I := 0 to Pred(DynArraySize(Arr)) do
                begin
                  TPointerJsonProc(e.CustomProc)(Arr, Writer);
                  Arr += ElSize;
                end;
          else
          end;
          exit;
        end;
      for I := 0 to Pred(DynArraySize(Arr)) do
        begin
          WriteField(ElType, Arr);
          Arr += ElSize;
        end;
    finally
      Writer.EndArray;
    end;
  end;
  procedure WriteVariant(const v: Variant);
  var
    I: SizeInt;
    d: Double;
  begin
    if VarIsArray(v) then
      begin
        Writer.BeginArray;
        for I := VarArrayLowBound(v, 1) to VarArrayHighBound(v, 1) do
          WriteVariant(v[I]);
        Writer.EndArray;
        exit;
      end;
    if VarIsEmpty(v) or VarIsNull(v) then
      begin
        Writer.AddNull;
        exit;
      end;
    case VarType(v) of
      varSmallInt, varInteger, varSingle, varShortInt, varDouble, varCurrency,
      varDate, varByte, varWord, varLongWord, varInt64, varDecimal, varQWord:
        begin
          d := v;
          Writer.Add(d);
        end;
      varBoolean:
        if Boolean(v) then
          Writer.AddTrue
        else
          Writer.AddFalse;
      varOleStr,
      varString,
      varUString:
        Writer.Add(string(v));
    else
      Writer.Add(UNKNOWN_ALIAS);
    end;
  end;
  procedure WriteClass(aTypeInfo: PTypeInfo; o: TObject); forward;
  procedure WriteClassProp(o: TObject; aPropInfo: PPropInfo);
  var
    pTypInfo: PTypeInfo;
    I: Int64;
    e: Extended;
    p: Pointer;
  begin
    pTypInfo := aPropInfo^.PropType;
    case pTypInfo^.Kind of
      tkInteger, tkChar, tkWChar, tkBool, tkInt64, tkQWord, tkUChar:
        begin
          I := GetOrdProp(o, aPropInfo);
          WriteField(pTypInfo, @I);
        end;
      tkFloat:
        begin
          e := GetFloatProp(o, aPropInfo);
          WriteField(pTypInfo, @e);
        end;
      tkSString, tkLString, tkAString:
        begin
          p := Pointer(GetStrProp(o, aPropInfo));
          WriteField(pTypInfo, @p);
        end;
      tkWString:
        begin
          p := Pointer(GetWideStrProp(o, aPropInfo));
          WriteField(pTypInfo, @p);
        end;
      tkVariant: WriteVariant(GetVariantProp(o, aPropInfo));
      tkClass: WriteClass(aPropInfo^.PropType, GetObjectProp(o, aPropInfo));
      tkDynArray:
        begin
          p := GetDynArrayProp(o, aPropInfo);
          WriteField(pTypInfo, @p);
        end;
      tkUString:
        begin
          p := Pointer(GetUnicodeStrProp(o, aPropInfo));
          WriteField(pTypInfo, @p);
        end;
    else
      Writer.Add(UNKNOWN_ALIAS);
    end;
  end;
  procedure WriteClass(aTypeInfo: PTypeInfo; o: TObject);
  var
    I, J: SizeInt;
    c: TCollection;
    Props: TPropInfoList;
    e: TPdoCacheEntry;
  begin
    if o = nil then
      begin
        Writer.AddNull;
        exit;
      end;
    if GetPdoEntry(aTypeInfo, e) and (e.Kind = ekClassJsonProc) then
      begin
        TClassJsonProc(e.CustomProc)(o, Writer);
        exit;
      end;
    if o is TCollection then
      begin
        c := TCollection(o);
        if c.Count = 0 then
          begin
            Writer.BeginArray;
            Writer.EndArray;
            exit;
          end;
        Props := TPropInfoList.Create(c.Items[0], tkProperties, False);
        try
          Writer.BeginArray;
          for I := 0 to Pred(c.Count) do
            begin
              Writer.BeginObject;
              for J := 0 to Pred(Props.Count) do
                begin
                  Writer.AddName(Props[J]^.Name);
                  WriteClassProp(c.Items[I], Props[J]);
                end;
              Writer.EndObject;
            end;
          Writer.EndArray;
        finally
          Props.Free;
        end;
        exit;
      end;
    Props := TPropInfoList.Create(o, tkProperties, False);
    try
      Writer.BeginObject;
      for I := 0 to Pred(Props.Count) do
        begin
          Writer.AddName(Props[I]^.Name);
          WriteClassProp(o, Props[I]);
        end;
      Writer.EndObject;
    finally
      Props.Free;
    end;
  end;
  procedure WriteObject(aTypeInfo, aData: Pointer);
  var
    e: TPdoCacheEntry;
  begin
    if GetPdoEntry(aTypeInfo, e) and (e.Kind = ekObjJsonProc) then
      TPointerJsonProc(e.CustomProc)(aData, Writer)
    else
      Writer.Add(UNKNOWN_ALIAS);
  end;
  procedure WriteField(aTypeInfo: PTypeInfo; aData: Pointer);
  begin
    if not (aTypeInfo^.Kind in SUPPORT_KINDS) then
      begin
        Writer.Add(UNKNOWN_ALIAS);
        exit;
      end;
    case aTypeInfo^.Kind of
      tkInteger, tkInt64, tkQWord:
        WriteInteger(GetTypeData(aTypeInfo), aData);
      tkFloat:
        WriteFloat(GetTypeData(aTypeInfo), aData);
      tkChar:
        Writer.Add(string(PChar(aData)^)); //////////////
      tkSString:
        Writer.Add(PShortString(aData)^);
      tkLString, tkAString:
        Writer.Add(PString(aData)^);  ////////////
      tkWString:
        Writer.Add(string(PWideString(aData)^)); //////////////
      tkVariant:
        WriteVariant(PVariant(aData)^);
      tkArray:
        WriteArray(aTypeInfo, aData);
      tkRecord:
        WriteRecord(aTypeInfo, aData);
      tkClass:
        WriteClass(aTypeInfo, TObject(aData^));
      tkObject:
        WriteObject(aTypeInfo, aData);
      tkWChar:
        Writer.Add(string(widestring(PWideChar(aData)^))); //////////
      tkBool:
        WriteBool(GetTypeData(aTypeInfo), aData);
      tkDynArray:
        WriteDynArray(aTypeInfo, aData);
      tkUString:
        Writer.Add(string(PUnicodeString(aData)^)); ///////////
      tkUChar:
        Writer.Add(string(unicodestring(PUnicodeChar(aData)^)));/////////
    else
    end;
  end;
var
  WriterRef: specialize TGAutoRef<TJsonStrWriter>;
begin
  Result := '';
  if aTypeInfo = nil then exit;
  Writer := WriterRef;
  WriteField(aTypeInfo, @aValue);
  Result := Writer.JsonString;
end;

initialization
  InitCriticalSection(GlobLock);
finalization
  DoneCriticalSection(GlobLock);
end.
