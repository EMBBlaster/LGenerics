{****************************************************************************
*                                                                           *
*   This file is part of the LGenerics package.                             *
*   Generic hash table implementations for internal use.                    *
*                                                                           *
*   Copyright(c) 2018-2019 A.Koverdyaev(avk)                                *
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
unit LGHashTable;

{$mode objfpc}{$H+}
{$INLINE ON}
{$MODESWITCH ADVANCEDRECORDS}
{$MODESWITCH NESTEDPROCVARS}

interface

uses

  SysUtils,
  math,
  LGUtils,
  {%H-}LGHelpers,
  LGStrConst;

type

  generic TGAbstractHashTable<TKey, TEntry> = class abstract
  strict protected
  const
    MIN_LOAD_FACTOR  = 0.25;

  type
    TAbstractHashTable = specialize TGAbstractHashTable<TKey, TEntry>;
    THashTableClass  = class of TAbstractHashTable;

  var
    FCount,
    FExpandTreshold: SizeInt;
    FLoadFactor: Single;
    procedure AllocList(aCapacity: SizeInt); virtual; abstract;
    function  GetCapacity: SizeInt; virtual; abstract;
    procedure SetLoadFactor(aValue: Single); virtual; abstract;
    function  GetFillRatio: Single;
    function  RestrictLoadFactor(aValue: Single): Single;
    class function EstimateCapacity(aCount: SizeInt; aLoadFactor: Single): SizeInt; virtual; abstract;
  public
  type
    PEntry           = ^TEntry;
    TEntryEvent      = procedure(p: PEntry) of object;
    TTest            = specialize TGTest<TKey>;
    TOnTest          = specialize TGOnTest<TKey>;
    TNestTest        = specialize TGNestTest<TKey>;
    TEntryTest       = function(p: PEntry): Boolean of object;
    TEntryEnumerator = specialize TGEnumerator<PEntry>;

    TSearchResult = record
      case Integer of
        0: (FoundIndex, InsertIndex: SizeInt);
        1: (Node, PrevNode: Pointer);
    end;

    class function DefaultLoadFactor: Single; virtual; abstract;
    class function MaxLoadFactor: Single; virtual; abstract;
    class function MinLoadFactor: Single; static; inline;
    constructor CreateEmpty; virtual;
    constructor CreateEmpty(aLoadFactor: Single); virtual;
    constructor Create; virtual;
    constructor Create(aCapacity: SizeInt); virtual;
    constructor Create(aLoadFactor: Single); virtual;
    constructor Create(aCapacity: SizeInt; aLoadFactor: Single); virtual;
    function  GetEnumerator: TEntryEnumerator; virtual; abstract;
    function  Clone: TAbstractHashTable; virtual; abstract;
    procedure Clear; virtual; abstract;
    procedure EnsureCapacity(aValue: SizeInt); virtual; abstract;
    procedure TrimToFit; virtual; abstract;
  { return True if aKey found, otherwise insert garbage entry and return False }
    function  FindOrAdd(constref aKey: TKey; out e: PEntry; out aRes: TSearchResult): Boolean; virtual;abstract; overload;
    function  Find(constref aKey: TKey; out aPos: TSearchResult): PEntry; virtual; abstract;
    function  Remove(constref aKey: TKey): Boolean; virtual; abstract;
    procedure RemoveAt(constref aPos: TSearchResult); virtual; abstract;
    function  RemoveIf(aTest: TTest; aOnRemove: TEntryEvent = nil): SizeInt; virtual; abstract;
    function  RemoveIf(aTest: TOnTest; aOnRemove: TEntryEvent = nil): SizeInt; virtual; abstract;
    function  RemoveIf(aTest: TNestTest; aOnRemove: TEntryEvent = nil): SizeInt; virtual; abstract;
    function  RemoveIf(aTest: TEntryTest; aOnRemove: TEntryEvent = nil): SizeInt; virtual; abstract;
    property  Count: SizeInt read FCount;
  { The number of elements that can be written without rehashing }
    property  ExpandTreshold: SizeInt read FExpandTreshold;
    property  Capacity: SizeInt read GetCapacity;
    property  LoadFactor: Single read FLoadFactor write SetLoadFactor;
    property  FillRatio: Single read GetFillRatio;
  end;

  { TGOpenAddressing }

  generic TGOpenAddressing<TKey, TEntry, TEqRel, TProbeSeq> = class abstract(
    specialize TGAbstractHashTable<TKey, TEntry>)
  strict protected
  const
    USED_FLAG: SizeInt      = SizeInt(SizeInt(1) shl Pred(BitSizeOf(SizeInt)));

  type
    TNode = record
      Hash: SizeInt;
      Data: TEntry;
    end;
    PNode = ^TNode;

    TNodeList = array of TNode;

    TEnumerator = class(TEntryEnumerator)
    private
      FList: PNode;
      FCurrIndex,
      FLastIndex: SizeInt;
    protected
      function  GetCurrent: PEntry; override;
    public
      constructor Create(constref aList: TNodeList);
      function  MoveNext: Boolean; override;
      procedure Reset; override;
    end;

  const
    NODE_SIZE = SizeOf(TNode);
    {$PUSH}{$J+}
    MAX_CAPACITY: SizeInt = MAX_CONTAINER_SIZE div NODE_SIZE;
    {$POP}

  type
    TFakeNode = {$IFNDEF FPC_REQUIRES_PROPER_ALIGNMENT}array[0..Pred(NODE_SIZE)] of Byte{$ELSE}TNode{$ENDIF};

  var
    FList: TNodeList;
    procedure AllocList(aCapacity: SizeInt); override;
    function  GetCapacity: SizeInt; override;
    procedure SetLoadFactor(aValue: Single); override;
    procedure UpdateExpandTreshold;
    procedure Rehash(var aTarget: TNodeList); virtual;
    procedure Resize(aNewCapacity: SizeInt);
    procedure Expand;
    function  DoFind(constref aKey: TKey; aKeyHash: SizeInt): TSearchResult; virtual;
    procedure DoRemove(aIndex: SizeInt); virtual; abstract;
    class function EstimateCapacity(aCount: SizeInt; aLoadFactor: Single): SizeInt; override;
    class constructor Init;
  public
    class function DefaultLoadFactor: Single; override;
    class function MaxLoadFactor: Single; override;
    function  GetEnumerator: TEntryEnumerator; override;
    procedure Clear; override;
    procedure EnsureCapacity(aValue: SizeInt); override;
    procedure TrimToFit; override;
    function  FindOrAdd(constref aKey: TKey; out e: PEntry; out aRes: TSearchResult): Boolean; override;
    function  Find(constref aKey: TKey; out aPos: TSearchResult): PEntry; override;
    function  Remove(constref aKey: TKey): Boolean; override;
    procedure RemoveAt(constref aPos: TSearchResult); override;
  end;

  TLPSeq = class
  const
    DEFAULT_LOAD_FACTOR: Single = 0.55;
    MAX_LOAD_FACTOR: Single     = 0.90;

    class function NextProbe(aPrevPos, aIndex: SizeInt): SizeInt; static; inline;
  end;

  { TGOpenAddrLP implements open addressing hash table with linear probing(step = 1) }
  generic TGOpenAddrLP<TKey, TEntry, TEqRel> = class(specialize TGOpenAddressing<TKey, TEntry, TEqRel, TLPSeq>)
  strict protected
    procedure DoRemove(aIndex: SizeInt); override;
  public
    function  Clone: TAbstractHashTable; override;
    function  RemoveIf(aTest: TTest; aOnRemove: TEntryEvent = nil): SizeInt; override;
    function  RemoveIf(aTest: TOnTest; aOnRemove: TEntryEvent = nil): SizeInt; override;
    function  RemoveIf(aTest: TNestTest; aOnRemove: TEntryEvent = nil): SizeInt; override;
    function  RemoveIf(aTest: TEntryTest; aOnRemove: TEntryEvent = nil): SizeInt; override;
  end;

  { TGOpenAddrTombstones }

  generic TGOpenAddrTombstones<TKey, TEntry, TEqRel, TProbeSeq> = class abstract(
    specialize TGOpenAddressing<TKey, TEntry, TEqRel, TProbeSeq>)
  strict protected
  const
    TOMBSTONE: SizeInt = SizeInt(1);

  var
    FTombstonesCount: SizeInt;
    function  BusyCount: SizeInt; inline;
    procedure Rehash(var aTarget: TNodeList); override;
    function  DoFind(constref aKey: TKey; aKeyHash: SizeInt): TSearchResult; override;
    procedure DoRemove(aIndex: SizeInt); override;
  public
    procedure Clear; override;
    procedure ClearTombstones; inline;
    function  FindOrAdd(constref aKey: TKey; out e: PEntry; out aRes: TSearchResult): Boolean; override;
    function  RemoveIf(aTest: TTest; aOnRemove: TEntryEvent = nil): SizeInt; override;
    function  RemoveIf(aTest: TOnTest; aOnRemove: TEntryEvent = nil): SizeInt; override;
    function  RemoveIf(aTest: TNestTest; aOnRemove: TEntryEvent = nil): SizeInt; override;
    function  RemoveIf(aTest: TEntryTest; aOnRemove: TEntryEvent = nil): SizeInt; override;
    property  TombstonesCount: SizeInt read FTombstonesCount;
  end;

  { TGOpenAddrLPT implements open addressing tombstones hash table with linear probing and lazy deletion}
  generic TGOpenAddrLPT<TKey, TEntry, TEqRel> = class(
    specialize TGOpenAddrTombstones<TKey, TEntry, TEqRel, TLPSeq>)
    function Clone: TAbstractHashTable; override;
  end;

  TQP12Seq = class
  const
    DEFAULT_LOAD_FACTOR: Single = 0.50;
    MAX_LOAD_FACTOR: Single     = 0.75;
    class function NextProbe(aPrevPos, aIndex: SizeInt): SizeInt; static; inline;
  end;

  { TGOpenAddrQP implements open addressing hash table with quadratic probing(c1 = 1/2, c2 = 1/2) }
  generic TGOpenAddrQP<TKey, TEntry, TEqRel> = class(
    specialize TGOpenAddrTombstones<TKey, TEntry, TEqRel, TQP12Seq>)
    function Clone: TAbstractHashTable; override;
  end;

{.$DEFINE ORDEREDHASHTABLE_ENABLE_PAGEDNODEMANAGER}{ if uncomment define, TGOrderedHashTable
                                                     will use TGPageNodeManager }
  { TGOrderedHashTable }
  generic TGOrderedHashTable<TKey, TEntry, TEqRel> = class(specialize TGAbstractHashTable<TKey, TEntry>)
  public
  type
    PNode = ^TNode;

    TNode = record
      ChainNext,
      Prior,
      Next: PNode;
      Hash: SizeInt;
      Data: TEntry;
      property  NextLink: PNode read ChainNext write ChainNext; //for node manager
    end;

  strict protected
  type
    TChainList = array of PNode;

    TEnumerator = class(TEntryEnumerator)
    private
      FHead,
      FCurrNode: PNode;
      FInCycle: Boolean;
    protected
      function  GetCurrent: PEntry; override;
    public
      constructor Create(aHead: PNode);
      function  MoveNext: Boolean; override;
      procedure Reset; override;
    end;

  public
  type
    TReverseEnumerator = class(TEntryEnumerator)
    protected
      FHead,
      FTail,
      FCurrNode: PNode;
      FInCycle: Boolean;
      function  GetCurrent: PEntry; override;
    public
      constructor Create(aTable: TGOrderedHashTable);
      function  MoveNext: Boolean; override;
      procedure Reset; override;
      property  Head: PNode read FHead;
      property  Tail: PNode read FTail;
    end;

  strict protected
  type
{$IFDEF ORDEREDHASHTABLE_ENABLE_PAGEDNODEMANAGER}
    TNodeManager = specialize TGPageNodeManager<TNode>;
{$ELSE ORDEREDHASHTABLE_ENABLE_PAGEDNODEMANAGER}
    TNodeManager = specialize TGNodeManager<TNode>;
{$ENDIF ORDEREDHASHTABLE_ENABLE_PAGEDNODEMANAGER}

  const
    DEFAULT_LOAD_FACTOR: Single = 1.0;
    MAX_LOAD_FACTOR: Single     = 4.0;
    MAX_CAPACITY                = (MAX_CONTAINER_SIZE shr 2) div SizeOf(Pointer);

  var
    FList: TChainList;
    FHead,
    FTail: PNode;
    FNodeManager: TNodeManager;
    FUpdateOnHit: Boolean;
    procedure AllocList(aCapacity: SizeInt); override;
    function  GetCapacity: SizeInt; override;
    procedure SetLoadFactor(aValue: Single); override;
    function  NewNode: PNode; inline;
    procedure DisposeNode(aNode: PNode); inline;
    procedure ClearChainList;
    procedure UpdateExpandTreshold;
    procedure Rehash(var aTarget: TChainList);
    procedure Resize(aNewCapacity: SizeInt);
    procedure Expand;
    function  DoAdd(aKeyHash: SizeInt): PNode;
    function  DoFind(constref aKey: TKey; aKeyHash: SizeInt): TSearchResult;
    procedure Add2Tail(aNode: PNode);
    procedure RemoveFromList(aNode: PNode);
    procedure RemoveNode(aNode: PNode);
    class function EstimateCapacity(aCount: SizeInt; aLoadFactor: Single): SizeInt; override;
  public
    class function DefaultLoadFactor: Single; override;
    class function MaxLoadFactor: Single;  override;
    constructor CreateEmpty; override;
    constructor CreateEmpty(aLoadFactor: Single); override;
    constructor Create; override;
    constructor Create(aCapacity: SizeInt); override;
    constructor Create(aLoadFactor: Single); override;
    constructor Create(aCapacity: SizeInt; aLoadFactor: Single); override;
    destructor Destroy; override;
    procedure Clear; override;
    function  Clone: TAbstractHashTable; override;
    procedure EnsureCapacity(aValue: SizeInt); override;
    procedure TrimToFit; override;
    function  GetEnumerator: TEntryEnumerator; override;
    function  GetReverseEnumerator: TReverseEnumerator;
  { return True if aKey found, otherwise insert empty Entry and return False }
    function  FindOrAdd(constref aKey: TKey; out e: PEntry; out aRes: TSearchResult): Boolean; override;
    function  Find(constref aKey: TKey; out aPos: TSearchResult): PEntry; override;
    function  Remove(constref aKey: TKey): Boolean; override;
    procedure RemoveAt(constref aPos: TSearchResult); override;
    function  RemoveIf(aTest: TTest; aOnRemove: TEntryEvent = nil): SizeInt; override;
    function  RemoveIf(aTest: TOnTest; aOnRemove: TEntryEvent = nil): SizeInt; override;
    function  RemoveIf(aTest: TNestTest; aOnRemove: TEntryEvent = nil): SizeInt; override;
    function  RemoveIf(aTest: TEntryTest; aOnRemove: TEntryEvent = nil): SizeInt; override;
    function  GetFirst: PEntry;
    function  GetLast: PEntry;
    property  Head: PNode read FHead;
    property  Tail: PNode read FTail;
    property  UpdateOnHit: Boolean read FUpdateOnHit write FUpdateOnHit;
  end;

{.$DEFINE CHAINHASHTABLE_ENABLE_PAGEDNODEMANAGER}{ if uncomment define, TGChainHashTable
                                                   will use TGPageNodeManager }
  { TGChainHashTable }
  generic TGChainHashTable<TKey, TEntry, TEqRel> = class(specialize TGAbstractHashTable<TKey, TEntry>)
  public
  type
    PNode = ^TNode;
    TNode = record
      Next: PNode;
      Hash: SizeInt;
      Data: TEntry;
      property  NextLink: PNode read Next write Next; //for node manager
    end;

  protected
  type
    TChainList = array of PNode;

    TEnumerator = class(TEntryEnumerator)
    private
      FList: TChainList;
      FCurrNode: PNode;
      FLastIndex,
      FCurrIndex: SizeInt;
    protected
      function  GetCurrent: PEntry; override;
    public
      constructor Create(constref aList: TChainList);
      function  MoveNext: Boolean; override;
      procedure Reset; override;
    end;
{$IFDEF CHAINHASHTABLE_ENABLE_PAGEDNODEMANAGER}
    TNodeManager = specialize TGPageNodeManager<TNode>;
{$ELSE CHAINHASHTABLE_ENABLE_PAGEDNODEMANAGER}
    TNodeManager = specialize TGNodeManager<TNode>;
{$ENDIF CHAINHASHTABLE_ENABLE_PAGEDNODEMANAGER}
  const
    DEFAULT_LOAD_FACTOR: Single = 1.0;
    MAX_LOAD_FACTOR: Single     = 4.0;
    MAX_CAPACITY                = (MAX_CONTAINER_SIZE shr 2) div SizeOf(Pointer);

  var
    FList: TChainList;
    FNodeManager: TNodeManager;
    procedure AllocList(aCapacity: SizeInt); override;
    function  GetCapacity: SizeInt; override;
    procedure SetLoadFactor(aValue: Single); override;
    function  NewNode: PNode; inline;
    procedure DisposeNode(aNode: PNode);
    procedure ClearList;
    procedure UpdateExpandTreshold;
    procedure Rehash(var aTarget: TChainList);
    procedure Resize(aNewCapacity: SizeInt);
    procedure Expand;
    function  DoAdd(aKeyHash: SizeInt): PNode;
    function  DoFind(constref aKey: TKey; aKeyHash: SizeInt): TSearchResult;
    procedure DoRemove(constref aPos: TSearchResult);
    class function EstimateCapacity(aCount: SizeInt; aLoadFactor: Single): SizeInt; override;
  public
    class function DefaultLoadFactor: Single; override;
    class function MaxLoadFactor: Single; override;
    constructor CreateEmpty; override;
    constructor CreateEmpty(aLoadFactor: Single); override;
    constructor Create; override;
    constructor Create(aCapacity: SizeInt); override;
    constructor Create(aLoadFactor: Single); override;
    constructor Create(aCapacity: SizeInt; aLoadFactor: Single); override;
    destructor Destroy; override;
    procedure Clear; override;
    function  Clone: TAbstractHashTable; override;
    procedure EnsureCapacity(aValue: SizeInt); override;
    procedure TrimToFit; override;
    function  GetEnumerator: TEntryEnumerator; override;
  { returns True if aKey found, otherwise insert empty Entry and return False }
    function  FindOrAdd(constref aKey: TKey; out e: PEntry; out aRes: TSearchResult): Boolean; override;
    function  Find(constref aKey: TKey; out aPos: TSearchResult): PEntry; override;
    function  Add(constref aKey: TKey): PNode; inline;
    function  Remove(constref aKey: TKey): Boolean; override;
    procedure RemoveAt(constref aPos: TSearchResult); override;
    function  RemoveIf(aTest: TTest; aOnRemove: TEntryEvent = nil): SizeInt; override;
    function  RemoveIf(aTest: TOnTest; aOnRemove: TEntryEvent = nil): SizeInt; override;
    function  RemoveIf(aTest: TNestTest; aOnRemove: TEntryEvent = nil): SizeInt; override;
    function  RemoveIf(aTest: TEntryTest; aOnRemove: TEntryEvent = nil): SizeInt; override;
  end;

  { TGHashTableLP: simplified version TGOpenAddrLP }
  generic TGHashTableLP<TKey, TEntry, TEqRel> = class
  strict protected
  type
    TNode = record
      Hash: SizeInt;
      Data: TEntry;
    end;
    PNode = ^TNode;

    TNodeList = array of TNode;

  const
    NODE_SIZE             = SizeOf(TNode);
    USED_FLAG: SizeInt    = SizeInt(SizeInt(1) shl Pred(BitSizeOf(SizeInt)));
    {$PUSH}{$J+}
    MAX_CAPACITY: SizeInt = MAX_CONTAINER_SIZE div NODE_SIZE;
    {$POP}

  type
    TFakeNode = {$IFNDEF FPC_REQUIRES_PROPER_ALIGNMENT}array[0..Pred(NODE_SIZE)] of Byte{$ELSE}TNode{$ENDIF};

  public
  type
    PEntry = ^TEntry;

    TEnumerator = record
    private
      FList: PNode;
      FCurrIndex,
      FLastIndex: SizeInt;
      function  GetCurrent: PEntry; inline;
    public
      constructor Create(constref aList: TNodeList);
      function  MoveNext: Boolean;
      procedure Reset; inline;
      property  Current: PEntry read GetCurrent;
    end;

    TRemovableEnumerator = record
    private
      FEnum: TEnumerator;
      FTable: TGHashTableLP;
      function  GetCurrent: PEntry; inline;
    public
      constructor Create(aTable: TGHashTableLP);
      function  MoveNext: Boolean;
      procedure RemoveCurrent; inline;
      procedure Reset; inline;
      property  Current: PEntry read GetCurrent;
    end;

  strict protected
    FList: TNodeList;
    FCount,
    FExpandTreshold: SizeInt;
    FLoadFactor: Single;
    function  RestrictLoadFactor(aValue: Single): Single; inline;
    function  GetCapacity: SizeInt; inline;
    procedure UpdateExpandTreshold; inline;
    procedure SetLoadFactor(aValue: Single);
    function  GetFillRatio: Single; inline;
    function  GetTableSize: SizeInt; inline;
    procedure AllocList(aCapacity: SizeInt);
    procedure Rehash(var aTarget: TNodeList);
    procedure Resize(aNewCapacity: SizeInt);
    procedure Expand;
    function  DoFind(constref aKey: TKey; aKeyHash: SizeInt): SizeInt;
    procedure DoRemove(aIndex: SizeInt);
    class function EstimateCapacity(aCount: SizeInt; aLoadFactor: Single): SizeInt; static; inline;
    class constructor Init;
  public
  const
    DEFAULT_LOAD_FACTOR: Single = 0.55;
    MAX_LOAD_FACTOR: Single     = 0.90;
    MIN_LOAD_FACTOR: Single     = 0.25;
    class function DefaultLoadFactor: Single; static; inline;
    class function MaxLoadFactor: Single; static; inline;
    class function MinLoadFactor: Single; static; inline;
    constructor CreateEmpty;
    constructor CreateEmpty(aLoadFactor: Single);
    constructor Create;
    constructor Create(aCapacity: SizeInt);
    constructor Create(aLoadFactor: Single);
    constructor Create(aCapacity: SizeInt; aLoadFactor: Single);
    function  GetEnumerator: TEnumerator;
    function  GetRemovableEnumerator: TRemovableEnumerator;
    procedure Clear;
    procedure EnsureCapacity(aValue: SizeInt);
    procedure TrimToFit;
    function  FindOrAdd(constref aKey: TKey; out e: PEntry; out aPos: SizeInt): Boolean;
    function  Find(constref aKey: TKey; out aPos: SizeInt): PEntry;
    function  Remove(constref aKey: TKey): Boolean;
    procedure RemoveAt(aPos: SizeInt); inline;
    property  Count: SizeInt read FCount;
    property  Capacity: SizeInt read GetCapacity;
  { The number of entries that can be written without rehashing }
    property  ExpandTreshold: SizeInt read FExpandTreshold;
    property  LoadFactor: Single read FLoadFactor write SetLoadFactor;
    property  FillRatio: Single read GetFillRatio;
  end;

  generic TGLiteHashTableLP<TKey, TEntry, TEqRel> = record
  private
  type
    TNode = record
      Hash: SizeInt;
      Data: TEntry;
    end;
    PNode = ^TNode;

    TNodeList = array of TNode;

  const
    NODE_SIZE             = SizeOf(TNode);
    USED_FLAG: SizeInt    = SizeInt(SizeInt(1) shl Pred(BitSizeOf(SizeInt)));
    {$PUSH}{$J+}
    MAX_CAPACITY: SizeInt = MAX_CONTAINER_SIZE div NODE_SIZE;
    {$POP}
  type
    TFakeNode = {$IFNDEF FPC_REQUIRES_PROPER_ALIGNMENT}array[0..Pred(NODE_SIZE)] of Byte{$ELSE}TNode{$ENDIF};
    PLiteHashTableLP = ^TGLiteHashTableLP;

  public
  type
    PEntry = ^TEntry;

    TEnumerator = record
    private
      FList: PNode;
      FCurrIndex,
      FLastIndex: SizeInt;
      function  GetCurrent: PEntry; inline;
    public
      constructor Create(constref aList: TNodeList);
      function  MoveNext: Boolean;
      procedure Reset; inline;
      property  Current: PEntry read GetCurrent;
    end;

    TRemovableEnumerator = record
    private
      FEnum: TEnumerator;
      FTable: PLiteHashTableLP;
      function  GetCurrent: PEntry; inline;
    public
      constructor Create(aTable: PLiteHashTableLP);
      function  MoveNext: Boolean;
      procedure RemoveCurrent; inline;
      procedure Reset; inline;
      property  Current: PEntry read GetCurrent;
    end;

  private
    FList: TNodeList;
    FCount,
    FExpandTreshold: SizeInt;
    FLoadFactor: Single;
    function  RestrictLoadFactor(aValue: Single): Single; inline;
    procedure UpdateExpandTreshold;
    procedure SetLoadFactor(aValue: Single);
    function  GetCapacity: SizeInt;
    function  GetFillRatio: Single; inline;
    procedure AllocList(aCapacity: SizeInt);
    procedure Rehash(var aTarget: TNodeList);
    procedure Resize(aNewCapacity: SizeInt);
    procedure Expand;
    function  DoFind(constref aKey: TKey; aKeyHash: SizeInt): SizeInt;
    procedure DoRemove(aIndex: SizeInt);
    class function EstimateCapacity(aCount: SizeInt; aLoadFactor: Single): SizeInt; static; inline;
    class constructor Init;
    class operator Initialize(var ht: TGLiteHashTableLP);
    class operator Copy(constref aSrc: TGLiteHashTableLP; var aDst: TGLiteHashTableLP);
  public
  const
    DEFAULT_LOAD_FACTOR: Single = 0.55;
    MAX_LOAD_FACTOR: Single     = 0.90;
    MIN_LOAD_FACTOR: Single     = 0.25;

    function  GetEnumerator: TEnumerator;
    function  GetRemovableEnumerator: TRemovableEnumerator;
    procedure Clear;
    procedure EnsureCapacity(aValue: SizeInt);
    procedure TrimToFit;
  { returns True if aKey found, otherwise insert garbage entry and return False }
    function  FindOrAdd(constref aKey: TKey; out e: PEntry; out aPos: SizeInt): Boolean;
    function  Find(constref aKey: TKey; out aPos: SizeInt): PEntry;
    function  Remove(constref aKey: TKey): Boolean;
    procedure RemoveAt(aPos: SizeInt);
    property  Count: SizeInt read FCount;
  { The capacity of the table is the number of elements that can be written without rehashing,
    so real capacity is ExpandTreshold }
    property  Capacity: SizeInt read GetCapacity;
  { The number of entries that can be written without rehashing }
    property  ExpandTreshold: SizeInt read FExpandTreshold;
    property  LoadFactor: Single read FLoadFactor write SetLoadFactor;
    property  FillRatio: Single read GetFillRatio;
  end;

  { TGLiteChainHashTable: node based hash table with load factor 1.0;
      functor TKeyEqRel(equality relation) must provide:
        class function HashCode([const[ref]] aValue: TKey): SizeInt;
        class function Equal([const[ref]] L, R: TKey): Boolean; }
  generic TGLiteChainHashTable<TKey, TEntry, TKeyEqRel> = record
  public
  type
    PEntry = ^TEntry;

    TNode = record
      Next,
      Hash: SizeInt;
      Data: TEntry;
    end;
    PNode = ^TNode;

  private
  type
    TNodeList     = array of TNode;
    TChainList    = array of SizeInt;
    TSearchResult = record
      Index,
      PrevIndex: SizeInt;
    end;

  var
    FNodeList: TNodeList;
    FChainList: TChainList;
    FCount: SizeInt;
    function  GetCapacity: SizeInt; inline;
    function  GetNodeList: PNode; inline;
    procedure InitialAlloc; inline;
    procedure Rehash;
    procedure Resize(aNewCapacity: SizeInt);
    procedure Expand; inline;
    procedure RemoveFromChain(aIndex: SizeInt);
    procedure FixChain(aOldIndex, aNewIndex: SizeInt);
    function  DoFind(constref aKey: TKey; aHash: SizeInt; out aPos: TSearchResult): Boolean;
    function  DoAdd(aKeyHash: SizeInt): SizeInt;
    procedure DoRemove(constref aPos: TSearchResult);
    procedure DoRemoveIndex(aIndex: SizeInt);
    class operator Initialize(var ht: TGLiteChainHashTable);
    class operator Copy(constref aSrc: TGLiteChainHashTable; var aDst: TGLiteChainHashTable);
  public
    procedure Clear;
    procedure EnsureCapacity(aValue: SizeInt);
    procedure TrimToFit;
    function  FindOrAdd(constref aKey: TKey; out e: PEntry; out aIndex: SizeInt): Boolean;
    function  Find(constref aKey: TKey; out aIndex: SizeInt): PEntry;
    function  Remove(constref aKey: TKey): Boolean;
    procedure RemoveIndex(aIndex: SizeInt); inline;
    property  Count: SizeInt read FCount;
    property  Capacity: SizeInt read GetCapacity;
    property  NodeList: PNode read GetNodeList;
  end;

  { TGLiteIntHashTable: for integer keys only}
  generic TGLiteIntHashTable<TKey, TEntry> = record
  private
  type
    TNode = record
      Hash: SizeInt;
      Data: TEntry;
    end;
    PNode = ^TNode;

    TNodeList = array of TNode;

  const
    NODE_SIZE             = SizeOf(TNode);
    USED_FLAG: SizeInt    = SizeInt(1);
    {$PUSH}{$J+}
    MAX_CAPACITY: SizeInt = MAX_CONTAINER_SIZE div NODE_SIZE;
    {$POP}

  type
    TFakeNode  = {$IFNDEF FPC_REQUIRES_PROPER_ALIGNMENT}array[0..Pred(NODE_SIZE)] of Byte{$ELSE}TNode{$ENDIF};
    PHashTable = ^TGLiteIntHashTable;

  public
  type
    PEntry = ^TEntry;

    TEnumerator = record
    private
      FList: PNode;
      FCurrIndex,
      FLastIndex: SizeInt;
      function  GetCurrent: PEntry; inline;
    public
      function  MoveNext: Boolean;
      procedure Reset;
      property  Current: PEntry read GetCurrent;
    end;

    TRemovableEnumerator = record
    private
      FEnum: TEnumerator;
      FTable: PHashTable;
      function  GetCurrent: PEntry; inline;
    public
      constructor Create(aTable: PHashTable);
      function  MoveNext: Boolean;
      procedure RemoveCurrent; inline;
      procedure Reset;
      property  Current: PEntry read GetCurrent;
    end;

  private
    FList: TNodeList;
    FCount,
    FShift: SizeInt;
    function  GetExpandTreshold: SizeInt; inline;
    function  GetCapacity: SizeInt; inline;
    procedure Rehash(var aTarget: TNodeList);
    procedure Resize(aNewCapacity: SizeInt);
    procedure Expand;
    function  DoFind(aKey: TKey; aKeyHash: SizeInt): SizeInt;
    procedure DoRemove(aIndex: SizeInt);
    class function HashCode(aValue: TKey): SizeInt; static; //inline;
    class constructor Init;
    class operator Initialize(var ht: TGLiteIntHashTable);
    class operator Copy(constref aSrc: TGLiteIntHashTable; var aDst: TGLiteIntHashTable);
  public
    function  GetEnumerator: TEnumerator;
    function  GetRemovableEnumerator: TRemovableEnumerator;
    procedure Clear;
    procedure MakeEmpty;
    procedure EnsureCapacity(aValue: SizeInt);
    procedure TrimToFit;
    function  Contains(aKey: TKey): Boolean; inline;
  { returns True if aKey found, otherwise insert garbage entry and return False }
    function  FindOrAdd(aKey: TKey; out e: PEntry; out aPos: SizeInt): Boolean;
    function  Find(aKey: TKey): PEntry;
    function  FindFirstKey(out aKey: TKey): Boolean;
    function  Remove(aKey: TKey): Boolean;
    procedure RemoveAt(aPos: SizeInt);
    property  Count: SizeInt read FCount;
    property  Capacity: SizeInt read GetCapacity;
  { The number of entries that can be written without rehashing }
    property  ExpandTreshold: SizeInt read GetExpandTreshold;
    property  Size: SizeInt read GetCapacity;
  end;

const
  SLOT_NOT_FOUND: SizeInt = Low(SizeInt);

implementation
{$Q-}{$B-}{$COPERATORS ON}{$POINTERMATH ON}

{ TGAbstractHashTable }

function TGAbstractHashTable.GetFillRatio: Single;
var
  c: SizeInt;
begin
  c := Capacity;
  if c > 0 then
    Result := Count / c
  else
    Result := 0.0;
end;

function TGAbstractHashTable.RestrictLoadFactor(aValue: Single): Single;
begin
  Result := Math.Min(Math.Max(aValue, MIN_LOAD_FACTOR), MaxLoadFactor);
end;

class function TGAbstractHashTable.MinLoadFactor: Single;
begin
  Result := MIN_LOAD_FACTOR;
end;

constructor TGAbstractHashTable.CreateEmpty;
begin
  FLoadFactor := DefaultLoadFactor;
end;

constructor TGAbstractHashTable.CreateEmpty(aLoadFactor: Single);
begin
  FLoadFactor := RestrictLoadFactor(aLoadFactor);
end;

constructor TGAbstractHashTable.Create;
begin
  FLoadFactor := DefaultLoadFactor;
  AllocList(DEFAULT_CONTAINER_CAPACITY);
end;

constructor TGAbstractHashTable.Create(aCapacity: SizeInt);
begin
  FLoadFactor := DefaultLoadFactor;
  AllocList(EstimateCapacity(aCapacity, LoadFactor));
end;

constructor TGAbstractHashTable.Create(aLoadFactor: Single);
begin
  FLoadFactor := RestrictLoadFactor(aLoadFactor);
  AllocList(DEFAULT_CONTAINER_CAPACITY);
end;

constructor TGAbstractHashTable.Create(aCapacity: SizeInt; aLoadFactor: Single);
begin
  FLoadFactor := RestrictLoadFactor(aLoadFactor);
  AllocList(EstimateCapacity(aCapacity, LoadFactor));
end;

{ TGOpenAddressing.TEnumerator }

function TGOpenAddressing.TEnumerator.GetCurrent: PEntry;
begin
  Result := @FList[FCurrIndex].Data;
end;

constructor TGOpenAddressing.TEnumerator.Create(constref aList: TNodeList);
begin
  FList := Pointer(aList);
  FLastIndex := System.High(aList);
  FCurrIndex := NULL_INDEX;
end;

function TGOpenAddressing.TEnumerator.MoveNext: Boolean;
begin
  repeat
    if FCurrIndex >= FLastIndex then
      exit(False);
    Inc(FCurrIndex);
    Result := FList[FCurrIndex].Hash and USED_FLAG <> 0;
  until Result;
end;

procedure TGOpenAddressing.TEnumerator.Reset;
begin
  FCurrIndex := NULL_INDEX;
end;

{ TGOpenAddressing }

procedure TGOpenAddressing.AllocList(aCapacity: SizeInt);
begin
  if aCapacity > 0 then
    begin
      aCapacity := Math.Min(aCapacity, MAX_CAPACITY);
      if not IsTwoPower(aCapacity) then
        aCapacity := LGUtils.RoundUpTwoPower(aCapacity);
    end
  else
    aCapacity := DEFAULT_CONTAINER_CAPACITY;
  System.SetLength(FList, aCapacity);
  UpdateExpandTreshold;
end;

function TGOpenAddressing.GetCapacity: SizeInt;
begin
  Result := System.Length(FList);
end;

procedure TGOpenAddressing.SetLoadFactor(aValue: Single);
begin
  aValue := RestrictLoadFactor(aValue);
  if aValue <> LoadFactor then
    begin
      FLoadFactor := aValue;
      UpdateExpandTreshold;
      if Count >= ExpandTreshold then
        Expand;
    end;
end;

procedure TGOpenAddressing.UpdateExpandTreshold;
begin
  if System.Length(FList) < MAX_CAPACITY then
    FExpandTreshold := Trunc(System.Length(FList) * FLoadFactor)
  else
    FExpandTreshold := High(SizeInt);
end;

procedure TGOpenAddressing.Rehash(var aTarget: TNodeList);
var
  h, I, J, Mask: SizeInt;
begin
  if Count > 0 then
    begin
      Mask := System.High(aTarget);
      for I := 0 to System.High(FList) do
        begin
          if FList[I].Hash and USED_FLAG <> 0 then
            begin
              h := FList[I].Hash and Mask;
              for J := 0 to Mask do
                begin
                  if aTarget[h].Hash = 0 then // -> target node is empty
                    begin
                      TFakeNode(aTarget[h]) := TFakeNode(FList[I]);
                      TFakeNode(FList[I]) := Default(TFakeNode);
                      break;
                    end;
                  h := TProbeSeq.NextProbe(h, J) and Mask;// probe sequence
                end;
            end;
        end;
    end;
end;

procedure TGOpenAddressing.Resize(aNewCapacity: SizeInt);
var
  List: TNodeList;
begin
  System.SetLength(List, aNewCapacity);
  Rehash(List);
  FList := List;
  UpdateExpandTreshold;
end;

procedure TGOpenAddressing.Expand;
var
  NewCapacity, OldCapacity: SizeInt;
begin
  OldCapacity := System.Length(FList);
  if OldCapacity > 0 then
    begin
      NewCapacity := Math.Min(MAX_CAPACITY, OldCapacity shl 1);
      if NewCapacity > OldCapacity then
        Resize(NewCapacity);
    end
  else
    AllocList(DEFAULT_CONTAINER_CAPACITY);
end;

function TGOpenAddressing.DoFind(constref aKey: TKey; aKeyHash: SizeInt): TSearchResult;
var
  I, Pos, h, Mask: SizeInt;
begin
  Mask := System.High(FList);
  aKeyHash := aKeyHash or USED_FLAG;
  Result.FoundIndex := NULL_INDEX;
  Result.InsertIndex := NULL_INDEX;
  Pos := aKeyHash and Mask;
  for I := 0 to Mask do
    begin
      h := FList[Pos].Hash;
      if h = 0 then                               // node empty => key not found
        begin
          Result.InsertIndex := Pos;
          exit;
        end
      else
        if (h = aKeyHash) and TEqRel.Equal(FList[Pos].Data.Key, aKey) then
          begin
            Result.FoundIndex := Pos;             // key found
            exit;
          end;
      Pos := TProbeSeq.NextProbe(Pos, I) and Mask;// probe sequence
    end;
end;

class function TGOpenAddressing.EstimateCapacity(aCount: SizeInt; aLoadFactor: Single): SizeInt;
begin
  if aCount > 0 then
    Result := LGUtils.RoundUpTwoPower(Math.Min(Ceil64(Double(aCount) / aLoadFactor), MAX_CAPACITY))
  else
    Result := DEFAULT_CONTAINER_CAPACITY;
end;

class constructor TGOpenAddressing.Init;
begin
  MAX_CAPACITY := LGUtils.RoundUpTwoPower(MAX_CAPACITY);
end;

class function TGOpenAddressing.DefaultLoadFactor: Single;
begin
  Result := TProbeSeq.DEFAULT_LOAD_FACTOR;
end;

class function TGOpenAddressing.MaxLoadFactor: Single;
begin
  Result := TProbeSeq.MAX_LOAD_FACTOR;
end;

function TGOpenAddressing.GetEnumerator: TEntryEnumerator;
begin
  Result := TEnumerator.Create(FList);
end;

procedure TGOpenAddressing.Clear;
begin
  FList := nil;
  FCount := 0;
  FExpandTreshold := 0;
end;

procedure TGOpenAddressing.EnsureCapacity(aValue: SizeInt);
var
  NewCapacity: SizeInt;
begin
  if aValue <= ExpandTreshold then
    exit;
  if aValue <= MAX_CAPACITY then
    begin
      NewCapacity := EstimateCapacity(aValue, LoadFactor);
      if NewCapacity <> System.Length(FList) then
        Resize(NewCapacity);
    end
  else
    raise ELGCapacityExceed.CreateFmt(SEClassCapacityExceedFmt, [ClassName, aValue]);
end;

procedure TGOpenAddressing.TrimToFit;
var
  NewCapacity: SizeInt;
begin
  if Count > 0 then
    begin
      NewCapacity := EstimateCapacity(Count, LoadFactor);
      if NewCapacity < System.Length(FList) then
        Resize(NewCapacity);
    end
  else
    Clear;
end;

function TGOpenAddressing.FindOrAdd(constref aKey: TKey; out e: PEntry; out aRes: TSearchResult): Boolean;
var
  h: SizeInt;
begin
  if FList = nil then
    AllocList(DEFAULT_CONTAINER_CAPACITY);
  h := TEqRel.HashCode(aKey);
  aRes := DoFind(aKey, h);
  Result := aRes.FoundIndex >= 0; // key found?
  if not Result then              // key not found
    begin
      if Count >= ExpandTreshold then
        begin
          Expand;
          aRes := DoFind(aKey, h);
        end;
      if aRes.InsertIndex > NULL_INDEX then
        begin
          FList[aRes.InsertIndex].Hash := h or USED_FLAG;
          aRes.FoundIndex := aRes.InsertIndex;
          Inc(FCount);
        end
      else
        raise ELGCapacityExceed.CreateFmt(SEClassCapacityExceedFmt, [ClassName, Succ(Count)]);
    end;
  e := @FList[aRes.FoundIndex].Data;
end;

function TGOpenAddressing.Find(constref aKey: TKey; out aPos: TSearchResult): PEntry;
begin
  Result := nil;
  if Count > 0 then
    begin
      aPos := DoFind(aKey, TEqRel.HashCode(aKey));
      if aPos.FoundIndex >= 0 then
        Result := @FList[aPos.FoundIndex].Data;
    end;
end;

function TGOpenAddressing.Remove(constref aKey: TKey): Boolean;
var
  p: TSearchResult;
begin
  if Count > 0 then
    begin
      p := DoFind(aKey, TEqRel.HashCode(aKey));
      if p.FoundIndex >= 0 then
        begin
          DoRemove(p.FoundIndex);
          exit(True);
        end;
    end;
  Result := False;
end;

procedure TGOpenAddressing.RemoveAt(constref aPos: TSearchResult);
begin
  if (aPos.FoundIndex >= 0) and (aPos.FoundIndex <= System.High(FList)) then
    DoRemove(aPos.FoundIndex);
end;

{ TLPSeq }

class function TLPSeq.NextProbe(aPrevPos, aIndex: SizeInt): SizeInt;
begin
  Assert(aIndex = aIndex);
  Result := Succ(aPrevPos);
end;

{ TGOpenAddrLP }

procedure TGOpenAddrLP.DoRemove(aIndex: SizeInt);
var
  I, h, Gap, Mask: SizeInt;
begin
  Mask := System.High(FList);
  FList[aIndex].Hash := 0;
  FList[aIndex].Data := Default(TEntry);
  Gap := aIndex;
  aIndex := Succ(aIndex) and Mask;
  Dec(FCount);
  for I := 0 to Mask do
    begin
      h := FList[aIndex].Hash;
      if h <> 0 then
        begin
          h := h and Mask;
          if (h <> aIndex) and (Succ(aIndex - h + Mask) and Mask >= Succ(aIndex - Gap + Mask) and Mask) then
            begin
              TFakeNode(FList[Gap]) := TFakeNode(FList[aIndex]);
              TFakeNode(FList[aIndex]) := Default(TFakeNode);
              Gap := aIndex;
            end;
          aIndex := Succ(aIndex) and Mask;
        end
      else
        break;
    end;
end;

function TGOpenAddrLP.Clone: TAbstractHashTable;
var
  c: TGOpenAddrLP;
begin
  c := TGOpenAddrLP.CreateEmpty(LoadFactor);
  c.FList := System.Copy(FList);
  c.FCount := Count;
  c.FExpandTreshold := ExpandTreshold;
  Result := c;
end;

function TGOpenAddrLP.RemoveIf(aTest: TTest; aOnRemove: TEntryEvent): SizeInt;
var
  I: SizeInt;
begin
  Result := 0;
  if Count > 0 then
    begin
      I := 0;
      while I <= Pred(System.Length(FList)) do
        if (FList[I].Hash <> 0) and aTest(FList[I].Data.Key) then
          begin
            if aOnRemove <> nil then
              aOnRemove(@FList[I].Data);
            DoRemove(I);
            Inc(Result);
          end
        else
          Inc(I);
    end;
end;

function TGOpenAddrLP.RemoveIf(aTest: TOnTest; aOnRemove: TEntryEvent): SizeInt;
var
  I: SizeInt;
begin
  Result := 0;
  if Count > 0 then
    begin
      I := 0;
      while I <= Pred(System.Length(FList)) do
        if (FList[I].Hash <> 0) and aTest(FList[I].Data.Key) then
          begin
            if aOnRemove <> nil then
              aOnRemove(@FList[I].Data);
            DoRemove(I);
            Inc(Result);
          end
        else
          Inc(I);
    end;
end;

function TGOpenAddrLP.RemoveIf(aTest: TNestTest; aOnRemove: TEntryEvent): SizeInt;
var
  I: SizeInt;
begin
  Result := 0;
  if Count > 0 then
    begin
      I := 0;
      while I <= Pred(System.Length(FList)) do
        if (FList[I].Hash <> 0) and aTest(FList[I].Data.Key) then
          begin
            if aOnRemove <> nil then
              aOnRemove(@FList[I].Data);
            DoRemove(I);
            Inc(Result);
          end
        else
          Inc(I);
    end;
end;

function TGOpenAddrLP.RemoveIf(aTest: TEntryTest; aOnRemove: TEntryEvent): SizeInt;
var
  I: SizeInt;
begin
  Result := 0;
  if Count > 0 then
    begin
      I := 0;
      while I <= Pred(System.Length(FList)) do
        if (FList[I].Hash <> 0) and aTest(@FList[I].Data) then
          begin
            if aOnRemove <> nil then
              aOnRemove(@FList[I].Data);
            DoRemove(I);
            Inc(Result);
          end
        else
          Inc(I);
    end;
end;

{ TGOpenAddrTombstones }

function TGOpenAddrTombstones.BusyCount: SizeInt;
begin
  Result := Count + TombstonesCount;
end;

procedure TGOpenAddrTombstones.Rehash(var aTarget: TNodeList);
begin
  inherited;
  FTombstonesCount := 0;
end;

procedure TGOpenAddrTombstones.DoRemove(aIndex: SizeInt);
begin
  FList[aIndex].Hash := TOMBSTONE;
  FList[aIndex].Data := Default(TEntry);
  Inc(FTombstonesCount);
  Dec(FCount);
end;

procedure TGOpenAddrTombstones.Clear;
begin
  inherited;
  FTombstonesCount := 0;
end;

procedure TGOpenAddrTombstones.ClearTombstones;
begin
  Resize(System.Length(FList));
end;

function TGOpenAddrTombstones.FindOrAdd(constref aKey: TKey; out e: PEntry; out aRes: TSearchResult): Boolean;
var
  h: SizeInt;
begin
  if FList = nil then
    AllocList(DEFAULT_CONTAINER_CAPACITY);
  h := TEqRel.HashCode(aKey);
  aRes := DoFind(aKey, h);
  Result := aRes.FoundIndex >= 0; // key found?
  if not Result then              // key not found
    begin
      if BusyCount >= ExpandTreshold then
        begin
          if TombstonesCount >= Count shr 1 then  //todo: Count shr 1 ??? why ???
            ClearTombstones
          else
            Expand;
          aRes := DoFind(aKey, h);
        end;
      if aRes.InsertIndex >= 0 then
        begin
          if FList[aRes.InsertIndex].Hash = TOMBSTONE then
            Dec(FTombstonesCount);
          FList[aRes.InsertIndex].Hash := h or USED_FLAG;
          aRes.FoundIndex := aRes.InsertIndex;
          Inc(FCount);
        end
      else
        raise Exception.CreateFmt(SEClassCapacityExceedFmt, [ClassName, Succ(Count)]);
    end;
  e := @FList[aRes.FoundIndex].Data;
end;

function TGOpenAddrTombstones.RemoveIf(aTest: TTest; aOnRemove: TEntryEvent): SizeInt;
var
  I: SizeInt;
begin
  Result := 0;
  if Count > 0 then
    begin
      I := 0;
      while I <= Pred(System.Length(FList)) do
        begin
          if (FList[I].Hash and USED_FLAG <> 0) and aTest(FList[I].Data.Key) then
            begin
              if aOnRemove <> nil then
                aOnRemove(@FList[I].Data);
              DoRemove(I);
              Inc(Result);
            end;
          Inc(I);
        end;
    end;
end;

function TGOpenAddrTombstones.RemoveIf(aTest: TOnTest; aOnRemove: TEntryEvent): SizeInt;
var
  I: SizeInt;
begin
  Result := 0;
  if Count > 0 then
    begin
      I := 0;
      while I <= Pred(System.Length(FList)) do
        begin
          if (FList[I].Hash and USED_FLAG <> 0) and aTest(FList[I].Data.Key) then
            begin
              if aOnRemove <> nil then
                aOnRemove(@FList[I].Data);
              DoRemove(I);
              Inc(Result);
            end;
          Inc(I);
        end;
    end;
end;

function TGOpenAddrTombstones.RemoveIf(aTest: TNestTest; aOnRemove: TEntryEvent): SizeInt;
var
  I: SizeInt;
begin
  Result := 0;
  if Count > 0 then
    begin
      I := 0;
      while I <= Pred(System.Length(FList)) do
        begin
          if (FList[I].Hash and USED_FLAG <> 0) and aTest(FList[I].Data.Key) then
            begin
              if aOnRemove <> nil then
                aOnRemove(@FList[I].Data);
              DoRemove(I);
              Inc(Result);
            end;
          Inc(I);
        end;
    end;
end;

function TGOpenAddrTombstones.RemoveIf(aTest: TEntryTest; aOnRemove: TEntryEvent): SizeInt;
var
  I: SizeInt;
begin
  Result := 0;
  if Count > 0 then
    begin
      I := 0;
      while I <= Pred(System.Length(FList)) do
        begin
          if (FList[I].Hash and USED_FLAG <> 0 ) and aTest(@FList[I].Data) then
            begin
              if aOnRemove <> nil then
                aOnRemove(@FList[I].Data);
              DoRemove(I);
              Inc(Result);
            end;
          Inc(I);
        end;
    end;
end;

function TGOpenAddrTombstones.DoFind(constref aKey: TKey; aKeyHash: SizeInt): TSearchResult;
var
  I, Pos, h, Mask: SizeInt;
begin
  Mask := System.High(FList);
  aKeyHash := aKeyHash or USED_FLAG;
  Result.FoundIndex := NULL_INDEX;
  Result.InsertIndex := NULL_INDEX;
  Pos := aKeyHash and Mask;
  for I := 0 to Mask do
    begin
      h := FList[Pos].Hash;
      if h = 0 then                                // node empty => key not found
        begin
          if Result.InsertIndex = NULL_INDEX then  // if none tombstone found, remember first empty
            Result.InsertIndex := Pos;
          exit;
        end
      else
        if h = TOMBSTONE then
          begin
            if Result.InsertIndex = NULL_INDEX then// remember first tombstone position
              Result.InsertIndex := Pos;
          end
        else
          if (h = aKeyHash) and TEqRel.Equal(FList[Pos].Data.Key, aKey) then
            begin
              Result.FoundIndex := Pos;            // key found
              exit;
            end;
      Pos := TProbeSeq.NextProbe(Pos, I) and Mask; // probe sequence
    end;
end;

{ TGOpenAddrLPT }

function TGOpenAddrLPT.Clone: TAbstractHashTable;
var
  c: TGOpenAddrLPT;
begin
  c := TGOpenAddrLPT.CreateEmpty(LoadFactor);
  c.FList := System.Copy(FList);
  c.FCount := Count;
  c.FExpandTreshold := ExpandTreshold;
  c.FTombstonesCount := TombstonesCount;
  Result := c;
end;

{ TQP12Seq }

class function TQP12Seq.NextProbe(aPrevPos, aIndex: SizeInt): SizeInt;
begin
  Result := Succ(aPrevPos + aIndex);
end;


{ TGOpenAddrQP }

function TGOpenAddrQP.Clone: TAbstractHashTable;
var
  c: TGOpenAddrQP;
begin
  c := TGOpenAddrQP.CreateEmpty(LoadFactor);
  c.FList := System.Copy(FList);
  c.FCount := Count;
  c.FExpandTreshold := ExpandTreshold;
  c.FTombstonesCount := TombstonesCount;
  Result := c;
end;

{ TGOrderedHashTable.TEnumerator }

function TGOrderedHashTable.TEnumerator.GetCurrent: PEntry;
begin
  Result := @FCurrNode^.Data;
end;

constructor TGOrderedHashTable.TEnumerator.Create(aHead: PNode);
begin
  FHead := aHead;
end;

function TGOrderedHashTable.TEnumerator.MoveNext: Boolean;
var
  NextNode: PNode = nil;
begin
  if FCurrNode <> nil then
    NextNode := FCurrNode^.Next
  else
    if not FInCycle then
      begin
        NextNode := FHead;
        FInCycle := True;
      end;
  Result := NextNode <> nil;
  if Result then
    FCurrNode := NextNode;
end;

procedure TGOrderedHashTable.TEnumerator.Reset;
begin
  FCurrNode := nil;
  FInCycle := False;
end;

{ TGOrderedHashTable.TReverseEnumerator }

function TGOrderedHashTable.TReverseEnumerator.GetCurrent: PEntry;
begin
  Result := @FCurrNode^.Data;
end;

constructor TGOrderedHashTable.TReverseEnumerator.Create(aTable: TGOrderedHashTable);
begin
  FHead := aTable.Head;
  FTail := aTable.Tail;
  FCurrNode := nil;
end;

function TGOrderedHashTable.TReverseEnumerator.MoveNext: Boolean;
var
  NextNode: PNode = nil;
begin
  if FCurrNode <> nil then
    NextNode := FCurrNode^.Prior
  else
    if not FInCycle then
      begin
        NextNode := FTail;
        FInCycle := True;
      end;
  Result := NextNode <> nil;
  if Result then
    FCurrNode := NextNode;
end;

procedure TGOrderedHashTable.TReverseEnumerator.Reset;
begin
  FCurrNode := nil;
  FInCycle := False;
end;

{ TGOrderedHashTable }

procedure TGOrderedHashTable.AllocList(aCapacity: SizeInt);
begin
  if aCapacity > 0 then
    begin
      aCapacity := Math.Min(aCapacity, MAX_CAPACITY);
      if not IsTwoPower(aCapacity) then
        aCapacity := LGUtils.RoundUpTwoPower(aCapacity);
    end
  else
    aCapacity := DEFAULT_CONTAINER_CAPACITY;
  System.SetLength(FList, aCapacity);
  UpdateExpandTreshold;
end;

function TGOrderedHashTable.GetCapacity: SizeInt;
begin
  Result := System.Length(FList);
end;

procedure TGOrderedHashTable.SetLoadFactor(aValue: Single);
begin
  aValue := RestrictLoadFactor(aValue);
  if aValue <> LoadFactor then
    begin
      FLoadFactor := aValue;
      UpdateExpandTreshold;
      if Count >= ExpandTreshold then
        Expand;
    end;
end;

function TGOrderedHashTable.NewNode: PNode;
begin
  Result := FNodeManager.NewNode;
  Inc(FCount);
end;

procedure TGOrderedHashTable.DisposeNode(aNode: PNode);
begin
  if aNode <> nil then
    begin
      aNode^ := Default(TNode);
      FNodeManager.FreeNode(aNode);
      Dec(FCount);
    end;
end;

procedure TGOrderedHashTable.ClearChainList;
var
  CurrNode, NextNode: PNode;
begin
  CurrNode := Head;
  while CurrNode <> nil do
    begin
      NextNode := CurrNode^.Next;
      CurrNode^ := Default(TNode);
      FNodeManager.DisposeNode(CurrNode);
      CurrNode := NextNode;
    end;
  FHead := nil;
  FTail := nil;
  FList := nil;
  FCount := 0;
end;

procedure TGOrderedHashTable.UpdateExpandTreshold;
begin
  if System.Length(FList) < MAX_CAPACITY then
    FExpandTreshold := Trunc(System.Length(FList) * LoadFactor)
  else
    FExpandTreshold := High(SizeInt);
end;

procedure TGOrderedHashTable.Rehash(var aTarget: TChainList);
var
  Node, CurrNode, NextNode: PNode;
  I, Mask: SizeInt;
begin
  if Count > 0 then
    begin
      Mask := System.High(aTarget);
      for Node in FList do
        begin
          CurrNode := Node;
          while CurrNode <> nil do
            begin
              I := CurrNode^.Hash and Mask;
              NextNode := CurrNode^.ChainNext;
              CurrNode^.ChainNext := aTarget[I];
              aTarget[I] := CurrNode;
              CurrNode := NextNode;
            end;
        end;
    end;
end;

procedure TGOrderedHashTable.Resize(aNewCapacity: SizeInt);
var
  NewList: TChainList;
begin
  System.SetLength(NewList, aNewCapacity);
  Rehash(NewList);
  FList := NewList;
  UpdateExpandTreshold;
end;

procedure TGOrderedHashTable.Expand;
var
  NewCapacity, OldCapacity: SizeInt;
begin
  OldCapacity := System.Length(FList);
  if OldCapacity > 0 then
    begin
      NewCapacity := Math.Min(MAX_CAPACITY, OldCapacity shl 1);
      if NewCapacity > OldCapacity then
        Resize(NewCapacity);
    end
  else
    AllocList(DEFAULT_CONTAINER_CAPACITY);
end;

function TGOrderedHashTable.DoAdd(aKeyHash: SizeInt): PNode;
var
  I: SizeInt;
begin
  //add node to chain
  I := aKeyHash and System.High(FList);
  Result := NewNode;
  Result^.Hash := aKeyHash;
  Result^.ChainNext := FList[I];
  FList[I] := Result;
  Add2Tail(Result);
end;

function TGOrderedHashTable.DoFind(constref aKey: TKey; aKeyHash: SizeInt): TSearchResult;
var
  CurrNode, PrevNode: PNode;
begin
  CurrNode := FList[aKeyHash and System.High(FList)];
  PrevNode := nil;
  while CurrNode <> nil do
    begin
      if (CurrNode^.Hash = aKeyHash) and TEqRel.Equal(CurrNode^.Data.Key, aKey) then
        break;
      PrevNode := CurrNode;
      CurrNode := CurrNode^.ChainNext;
    end;
  Result.Node := CurrNode;
  Result.PrevNode := PrevNode;
  if UpdateOnHit and (CurrNode <> nil) and (Count > 1) then
    begin
      RemoveFromList(CurrNode);
      CurrNode^.Prior := nil;
      CurrNode^.Next := nil;
      Add2Tail(CurrNode);
    end;
end;

procedure TGOrderedHashTable.Add2Tail(aNode: PNode);
begin
  //add node to the tail of the list
  if Head = nil then
    FHead := aNode;
  if Tail <> nil then
    Tail^.Next := aNode;
  aNode^.Prior := Tail;
  FTail := aNode;
end;

procedure TGOrderedHashTable.RemoveFromList(aNode: PNode);
begin
  if aNode^.Prior <> nil then //is not head
    aNode^.Prior^.Next := aNode^.Next
  else
    FHead := aNode^.Next;

  if aNode^.Next <> nil then //is not tail
    aNode^.Next^.Prior := aNode^.Prior
  else
    FTail := aNode^.Prior;
end;

procedure TGOrderedHashTable.RemoveNode(aNode: PNode);
var
  CurrNode, PrevNode: PNode;
  Pos: TSearchResult;
begin
  CurrNode := FList[aNode^.Hash and System.High(FList)];
  PrevNode := nil;
  while CurrNode <> nil do
    begin
      if CurrNode = aNode then
        break;
      PrevNode := CurrNode;
      CurrNode := CurrNode^.ChainNext;
    end;
  Pos.Node := CurrNode;
  Pos.PrevNode := PrevNode;
  RemoveAt(Pos);
end;

class function TGOrderedHashTable.EstimateCapacity(aCount: SizeInt; aLoadFactor: Single): SizeInt;
begin
  if aCount > 0 then
    Result := LGUtils.RoundUpTwoPower(Math.Min(Ceil64(Double(aCount) / aLoadFactor), MAX_CAPACITY))
  else
    Result := DEFAULT_CONTAINER_CAPACITY;
end;

class function TGOrderedHashTable.DefaultLoadFactor: Single;
begin
  Result := DEFAULT_LOAD_FACTOR;
end;

class function TGOrderedHashTable.MaxLoadFactor: Single;
begin
  Result := MAX_LOAD_FACTOR;
end;

constructor TGOrderedHashTable.CreateEmpty;
begin
  inherited;
  FNodeManager := TNodeManager.Create;
end;

constructor TGOrderedHashTable.CreateEmpty(aLoadFactor: Single);
begin
  inherited CreateEmpty(aLoadFactor);
  FNodeManager := TNodeManager.Create;
end;

constructor TGOrderedHashTable.Create;
begin
  inherited Create;
  FNodeManager := TNodeManager.Create;
  FNodeManager.EnsureFreeCount(Capacity);
end;

constructor TGOrderedHashTable.Create(aCapacity: SizeInt);
begin
  inherited Create(aCapacity);
  FNodeManager := TNodeManager.Create;
  FNodeManager.EnsureFreeCount(Capacity);
end;

constructor TGOrderedHashTable.Create(aLoadFactor: Single);
begin
  inherited Create(aLoadFactor);
  FNodeManager := TNodeManager.Create;
  FNodeManager.EnsureFreeCount(Capacity);
end;

constructor TGOrderedHashTable.Create(aCapacity: SizeInt; aLoadFactor: Single);
begin
  inherited Create(aCapacity, aLoadFactor);
  FNodeManager := TNodeManager.Create;
  FNodeManager.EnsureFreeCount(Capacity);
end;

destructor TGOrderedHashTable.Destroy;
begin
  ClearChainList;
  FNodeManager.Free;
  inherited;
end;

procedure TGOrderedHashTable.Clear;
begin
  ClearChainList;
  FNodeManager.Clear;
  FExpandTreshold := 0;
end;

function TGOrderedHashTable.Clone: TAbstractHashTable;
var
  CurrNode, AddedNode: PNode;
begin
  Result := TGOrderedHashTable.Create(System.Length(FList), LoadFactor);
  CurrNode := FHead;
  while CurrNode <> nil do
    begin
      AddedNode := TGOrderedHashTable(Result).DoAdd(CurrNode^.Hash);
      AddedNode^.Data := CurrNode^.Data;
      CurrNode := CurrNode^.Next;
    end;
end;

procedure TGOrderedHashTable.EnsureCapacity(aValue: SizeInt);
var
  NewCapacity: SizeInt;
begin
  if aValue > ExpandTreshold then
    begin
      FNodeManager.EnsureFreeCount(aValue - Count);
      NewCapacity := EstimateCapacity(aValue, LoadFactor);
      if NewCapacity <> System.Length(FList) then
        Resize(NewCapacity);
    end;
end;

procedure TGOrderedHashTable.TrimToFit;
var
  NewCapacity: SizeInt;
begin
  if Count > 0 then
    begin
      NewCapacity := EstimateCapacity(Count, LoadFactor);
      if NewCapacity < System.Length(FList) then
        Resize(NewCapacity);
      FNodeManager.ClearFreeList;
    end
  else
    Clear;
end;

function TGOrderedHashTable.GetEnumerator: TEntryEnumerator;
begin
  Result := TEnumerator.Create(Head);
end;

function TGOrderedHashTable.GetReverseEnumerator: TReverseEnumerator;
begin
  Result := TReverseEnumerator.Create(Self);
end;

function TGOrderedHashTable.FindOrAdd(constref aKey: TKey; out e: PEntry; out aRes: TSearchResult): Boolean;
var
  h: SizeInt;
begin
  if FList = nil then
    AllocList(DEFAULT_CONTAINER_CAPACITY);
  h := TEqRel.HashCode(aKey);
  aRes := DoFind(aKey, h);
  Result := aRes.Node <> nil; // key found?
  if not Result then          // key not found
    begin
      if Count >= ExpandTreshold then
        Expand;
      aRes.Node := DoAdd(h);
    end;
  e := @PNode(aRes.Node)^.Data;
end;

function TGOrderedHashTable.Find(constref aKey: TKey; out aPos: TSearchResult): PEntry;
begin
  Result := nil;
  if Count > 0 then
    begin
      aPos := DoFind(aKey, TEqRel.HashCode(aKey));
      if aPos.Node <> nil then
        Result := @PNode(aPos.Node)^.Data;
    end;
end;

function TGOrderedHashTable.Remove(constref aKey: TKey): Boolean;
var
  sr: TSearchResult;
begin
  sr := DoFind(aKey, TEqRel.HashCode(aKey));
  if sr.Node <> nil then
    begin
      RemoveAt(sr);
      exit(True);
    end;
  Result := False;
end;

procedure TGOrderedHashTable.RemoveAt(constref aPos: TSearchResult);
var
  CurrNode, PrevNode: PNode;
begin
  if aPos.Node <> nil then
    begin
      PrevNode := aPos.PrevNode;
      CurrNode := aPos.Node;
      if PrevNode <> nil then  //is not head of chain
        PrevNode^.ChainNext := CurrNode^.ChainNext
      else
        FList[CurrNode^.Hash and System.High(FList)] := CurrNode^.ChainNext;
      RemoveFromList(CurrNode);
      DisposeNode(aPos.Node);
    end;
end;

function TGOrderedHashTable.RemoveIf(aTest: TTest; aOnRemove: TEntryEvent): SizeInt;
var
  CurrNode, NextNode: PNode;
begin
  Result := 0;
  CurrNode := FHead;
  while CurrNode <> nil do
    begin
      NextNode := CurrNode^.Next;
      if aTest(CurrNode^.Data.Key) then
        begin
          if aOnRemove <> nil then
            aOnRemove(@CurrNode^.Data);
          RemoveNode(CurrNode);
          Inc(Result);
        end;
      CurrNode := NextNode;
    end;
end;

function TGOrderedHashTable.RemoveIf(aTest: TOnTest; aOnRemove: TEntryEvent): SizeInt;
var
  CurrNode, NextNode: PNode;
begin
  Result := 0;
  CurrNode := FHead;
  while CurrNode <> nil do
    begin
      NextNode := CurrNode^.Next;
      if aTest(CurrNode^.Data.Key) then
        begin
          if aOnRemove <> nil then
            aOnRemove(@CurrNode^.Data);
          RemoveNode(CurrNode);
          Inc(Result);
        end;
      CurrNode := NextNode;
    end;
end;

function TGOrderedHashTable.RemoveIf(aTest: TNestTest; aOnRemove: TEntryEvent): SizeInt;
var
  CurrNode, NextNode: PNode;
begin
  Result := 0;
  CurrNode := FHead;
  while CurrNode <> nil do
    begin
      NextNode := CurrNode^.Next;
      if aTest(CurrNode^.Data.Key) then
        begin
          if aOnRemove <> nil then
            aOnRemove(@CurrNode^.Data);
          RemoveNode(CurrNode);
          Inc(Result);
        end;
      CurrNode := NextNode;
    end;
end;

function TGOrderedHashTable.RemoveIf(aTest: TEntryTest; aOnRemove: TEntryEvent): SizeInt;
var
  CurrNode, NextNode: PNode;
begin
  Result := 0;
  CurrNode := FHead;
  while CurrNode <> nil do
    begin
      NextNode := CurrNode^.Next;
      if aTest(@CurrNode^.Data) then
        begin
          if aOnRemove <> nil then
            aOnRemove(@CurrNode^.Data);
          RemoveNode(CurrNode);
          Inc(Result);
        end;
      CurrNode := NextNode;
    end;
end;

function TGOrderedHashTable.GetFirst: PEntry;
begin
  if Head <> nil then
    Result := @Head^.Data
  else
    Result := nil;
end;

function TGOrderedHashTable.GetLast: PEntry;
begin
  if Tail <> nil then
    Result := @Tail^.Data
  else
    Result := nil;
end;

{ TGChainHashTable.TEnumerator }

function TGChainHashTable.TEnumerator.GetCurrent: PEntry;
begin
  Result := @FCurrNode^.Data;
end;

constructor TGChainHashTable.TEnumerator.Create(constref aList: TChainList);
begin
  FList := aList;
  FLastIndex := High(aList);
  FCurrIndex := NULL_INDEX;
end;

function TGChainHashTable.TEnumerator.MoveNext: Boolean;
var
  NextNode: PNode = nil;
begin
  if FCurrNode <> nil then
    NextNode := FCurrNode^.Next;
  while NextNode = nil do
    begin
      if FCurrIndex >= FLastIndex then
        exit(False);
      Inc(FCurrIndex);
      NextNode := FList[FCurrIndex];
    end;
  FCurrNode := NextNode;
  Result := True;
end;

procedure TGChainHashTable.TEnumerator.Reset;
begin
  FCurrNode := nil;
  FCurrIndex := NULL_INDEX;
end;

{ TGChainHashTable }

procedure TGChainHashTable.AllocList(aCapacity: SizeInt);
begin
  if aCapacity > 0 then
    begin
      aCapacity := Math.Min(aCapacity, MAX_CAPACITY);
      if not IsTwoPower(aCapacity) then
        aCapacity := LGUtils.RoundUpTwoPower(aCapacity);
    end
  else
    aCapacity := DEFAULT_CONTAINER_CAPACITY;
  System.SetLength(FList, aCapacity);
  UpdateExpandTreshold;
end;

function TGChainHashTable.GetCapacity: SizeInt;
begin
  Result := System.Length(FList);
end;

procedure TGChainHashTable.SetLoadFactor(aValue: Single);
begin
  aValue := RestrictLoadFactor(aValue);
  if aValue <> LoadFactor then
    begin
      FLoadFactor := aValue;
      UpdateExpandTreshold;
      if Count >= ExpandTreshold then
        Expand;
    end;
end;

function TGChainHashTable.NewNode: PNode;
begin
  Result := FNodeManager.NewNode;
  Inc(FCount);
end;

procedure TGChainHashTable.DisposeNode(aNode: PNode);
begin
  if aNode <> nil then
    begin
      aNode^ := Default(TNode);
      FNodeManager.FreeNode(aNode);
      Dec(FCount);
    end;
end;

procedure TGChainHashTable.ClearList;
var
  Node, CurrNode, NextNode: PNode;
begin
  for Node in FList do
    begin
      CurrNode := Node;
      while CurrNode <> nil do
        begin
          NextNode := CurrNode^.Next;
          CurrNode^.Data := Default(TEntry);
          FNodeManager.DisposeNode(CurrNode);
          CurrNode := NextNode;
        end;
    end;
  FList := nil;
  FCount := 0;
end;

procedure TGChainHashTable.UpdateExpandTreshold;
begin
  if System.Length(FList) < MAX_CAPACITY then
    FExpandTreshold := Trunc(System.Length(FList) * LoadFactor)
  else
    FExpandTreshold := High(SizeInt);
end;

procedure TGChainHashTable.Rehash(var aTarget: TChainList);
var
  Node, CurrNode, NextNode: PNode;
  I, Mask: SizeInt;
begin
  if Count > 0 then
    begin
      Mask := System.High(aTarget);
      for Node in FList do
        begin
          CurrNode := Node;
          while CurrNode <> nil do
            begin
              I := CurrNode^.Hash and Mask;
              NextNode := CurrNode^.Next;
              CurrNode^.Next := aTarget[I];
              aTarget[I] := CurrNode;
              CurrNode := NextNode;
            end;
        end;
    end;
end;

procedure TGChainHashTable.Resize(aNewCapacity: SizeInt);
var
  NewList: TChainList;
begin
  System.SetLength(NewList, aNewCapacity);
  Rehash(NewList);
  FList := NewList;
  UpdateExpandTreshold;
end;

procedure TGChainHashTable.Expand;
var
  NewCapacity, OldCapacity: SizeInt;
begin
  OldCapacity := System.Length(FList);
  if OldCapacity > 0 then
    begin
      NewCapacity := Math.Min(MAX_CAPACITY, OldCapacity shl 1);
      if NewCapacity > OldCapacity then
        Resize(NewCapacity);
    end
  else
    AllocList(DEFAULT_CONTAINER_CAPACITY);
end;

function TGChainHashTable.DoAdd(aKeyHash: SizeInt): PNode;
var
  I: SizeInt;
begin
  //add node to chain
  I := aKeyHash and System.High(FList);
  Result := NewNode;
  Result^.Hash := aKeyHash;
  Result^.Next := FList[I];
  FList[I] := Result;
end;

function TGChainHashTable.DoFind(constref aKey: TKey; aKeyHash: SizeInt): TSearchResult;
var
  CurrNode, PrevNode: PNode;
begin
  CurrNode := FList[aKeyHash and System.High(FList)];
  PrevNode := nil;

  while CurrNode <> nil do
    begin
      if (CurrNode^.Hash = aKeyHash) and TEqRel.Equal(CurrNode^.Data.Key, aKey) then
        break;
      PrevNode := CurrNode;
      CurrNode := CurrNode^.Next;
    end;

  Result.Node := CurrNode;
  Result.PrevNode := PrevNode;
end;

procedure TGChainHashTable.DoRemove(constref aPos: TSearchResult);
begin
  if aPos.Node <> nil then
    begin
      if aPos.PrevNode <> nil then  //is not head of chain
        PNode(aPos.PrevNode)^.Next := PNode(aPos.Node)^.Next
      else
        FList[PNode(aPos.Node)^.Hash and System.High(FList)] := PNode(aPos.Node)^.Next;
      DisposeNode(aPos.Node);
    end;
end;

class function TGChainHashTable.EstimateCapacity(aCount: SizeInt; aLoadFactor: Single): SizeInt;
begin
  //aCount := Math.Min(Math.Max(aCount, 0), MAX_CAPACITY);
  if aCount > 0 then
    Result := LGUtils.RoundUpTwoPower(Math.Min(Ceil64(Double(aCount) / aLoadFactor), MAX_CAPACITY))
  else
    Result := DEFAULT_CONTAINER_CAPACITY;
end;

class function TGChainHashTable.DefaultLoadFactor: Single;
begin
  Result := DEFAULT_LOAD_FACTOR;
end;

class function TGChainHashTable.MaxLoadFactor: Single;
begin
  Result := MAX_LOAD_FACTOR;
end;

constructor TGChainHashTable.CreateEmpty;
begin
  inherited CreateEmpty;
  FNodeManager := TNodeManager.Create;
end;

constructor TGChainHashTable.CreateEmpty(aLoadFactor: Single);
begin
  inherited CreateEmpty(aLoadFactor);
  FNodeManager := TNodeManager.Create;
end;

constructor TGChainHashTable.Create;
begin
  inherited Create;
  FNodeManager := TNodeManager.Create;
  FNodeManager.EnsureFreeCount(Capacity);
end;

constructor TGChainHashTable.Create(aCapacity: SizeInt);
begin
  inherited Create(aCapacity);
  FNodeManager := TNodeManager.Create;
  FNodeManager.EnsureFreeCount(Capacity);
end;

constructor TGChainHashTable.Create(aLoadFactor: Single);
begin
  inherited Create(aLoadFactor);
  FNodeManager := TNodeManager.Create;
  FNodeManager.EnsureFreeCount(Capacity);
end;

constructor TGChainHashTable.Create(aCapacity: SizeInt; aLoadFactor: Single);
begin
  inherited Create(aCapacity, aLoadFactor);
  FNodeManager := TNodeManager.Create;
  FNodeManager.EnsureFreeCount(Capacity);
end;

destructor TGChainHashTable.Destroy;
begin
  ClearList;
  FNodeManager.Free;
  inherited;
end;

procedure TGChainHashTable.Clear;
begin
  ClearList;
  FNodeManager.Clear;
  FExpandTreshold := 0;
end;

function TGChainHashTable.Clone: TAbstractHashTable;
var
  AddedNode, CurrNode: PNode;
  I: SizeInt;
begin
  Result := TGChainHashTable.Create(System.Length(FList), LoadFactor);
  for I := 0 to System.High(FList) do
    begin
      CurrNode := FList[I];
      while CurrNode <> nil do
        begin
          AddedNode := TGChainHashTable(Result).DoAdd(CurrNode^.Hash);
          AddedNode^.Data := CurrNode^.Data;
          CurrNode := CurrNode^.Next;
        end;
    end;
end;

procedure TGChainHashTable.EnsureCapacity(aValue: SizeInt);
var
  NewCapacity: SizeInt;
begin
  if aValue > ExpandTreshold then
    begin
      FNodeManager.EnsureFreeCount(aValue - Count);
      NewCapacity := EstimateCapacity(aValue, LoadFactor);
      if NewCapacity <> System.Length(FList) then
        Resize(NewCapacity);
    end;
end;

procedure TGChainHashTable.TrimToFit;
var
  NewCapacity: SizeInt;
begin
  if Count > 0 then
    begin
      NewCapacity := EstimateCapacity(Count, LoadFactor);
      if NewCapacity < System.Length(FList) then
        Resize(NewCapacity);
      FNodeManager.ClearFreeList;
    end
  else
    Clear;
end;

function TGChainHashTable.GetEnumerator: TEntryEnumerator;
begin
  Result := TEnumerator.Create(FList);
end;

function TGChainHashTable.FindOrAdd(constref aKey: TKey; out e: PEntry; out aRes: TSearchResult): Boolean;
var
  h: SizeInt;
begin
  if FList = nil then
    AllocList(DEFAULT_CONTAINER_CAPACITY);
  h := TEqRel.HashCode(aKey);
  aRes := DoFind(aKey, h);
  Result := aRes.Node <> nil; // key found ?
  if not Result then          // key not found
    begin
      if Count >= ExpandTreshold then
        Expand;
      aRes.Node := DoAdd(h);
    end;
  e := @PNode(aRes.Node)^.Data;
end;

function TGChainHashTable.Find(constref aKey: TKey; out aPos: TSearchResult): PEntry;
begin
  if Count > 0 then
    begin
      aPos := DoFind(aKey, TEqRel.HashCode(aKey));
      if aPos.Node <> nil then
        Result := @PNode(aPos.Node)^.Data
      else
        Result := nil;
    end
  else
    Result := nil;
end;

function TGChainHashTable.Add(constref aKey: TKey): PNode;
begin
  if FList = nil then
    AllocList(DEFAULT_CONTAINER_CAPACITY);
  if Count >= ExpandTreshold then
    Expand;
  Result := DoAdd(TEqRel.HashCode(aKey));
end;

function TGChainHashTable.Remove(constref aKey: TKey): Boolean;
var
  p: TSearchResult;
begin
  p := DoFind(aKey, TEqRel.HashCode(aKey));
  Result := p.Node <> nil;
  if Result then
    DoRemove(p);
end;

procedure TGChainHashTable.RemoveAt(constref aPos: TSearchResult);
begin
  DoRemove(aPos);
end;

function TGChainHashTable.RemoveIf(aTest: TTest; aOnRemove: TEntryEvent): SizeInt;
var
  PrevNode, CurrNode, NextNode: PNode;
  I: SizeInt;
begin
  Result := 0;
  if Count > 0 then
    for I := 0 to Pred(System.Length(FList)) do
      begin
        CurrNode := FList[I];
        PrevNode := nil;
        while CurrNode <> nil do
          begin
            NextNode := CurrNode^.Next;
            if aTest(CurrNode^.Data.Key) then
              begin
                if PrevNode <> nil then
                  PrevNode^.Next := NextNode
                else
                  FList[I] := NextNode;
                if aOnRemove <> nil then
                  aOnRemove(@CurrNode^.Data);
                DisposeNode(CurrNode);
                Inc(Result);
              end
            else
              PrevNode := CurrNode;
            CurrNode := NextNode;
          end;
      end;
end;

function TGChainHashTable.RemoveIf(aTest: TOnTest; aOnRemove: TEntryEvent): SizeInt;
var
  PrevNode, CurrNode, NextNode: PNode;
  I: SizeInt;
begin
  Result := 0;
  if Count > 0 then
    for I := 0 to Pred(System.Length(FList)) do
      begin
        CurrNode := FList[I];
        PrevNode := nil;
        while CurrNode <> nil do
          begin
            NextNode := CurrNode^.Next;
            if aTest(CurrNode^.Data.Key) then
              begin
                if PrevNode <> nil then
                  PrevNode^.Next := NextNode
                else
                  FList[I] := NextNode;
                if aOnRemove <> nil then
                  aOnRemove(@CurrNode^.Data);
                DisposeNode(CurrNode);
                Inc(Result);
              end
            else
              PrevNode := CurrNode;
            CurrNode := NextNode;
          end;
      end;
end;

function TGChainHashTable.RemoveIf(aTest: TNestTest; aOnRemove: TEntryEvent): SizeInt;
var
  PrevNode, CurrNode, NextNode: PNode;
  I: SizeInt;
begin
  Result := 0;
  if Count > 0 then
    for I := 0 to Pred(System.Length(FList)) do
      begin
        CurrNode := FList[I];
        PrevNode := nil;
        while CurrNode <> nil do
          begin
            NextNode := CurrNode^.Next;
            if aTest(CurrNode^.Data.Key) then
              begin
                if PrevNode <> nil then
                  PrevNode^.Next := NextNode
                else
                  FList[I] := NextNode;
                if aOnRemove <> nil then
                  aOnRemove(@CurrNode^.Data);
                DisposeNode(CurrNode);
                Inc(Result);
              end
            else
              PrevNode := CurrNode;
            CurrNode := NextNode;
          end;
      end;
end;

function TGChainHashTable.RemoveIf(aTest: TEntryTest; aOnRemove: TEntryEvent): SizeInt;
var
  PrevNode, CurrNode, NextNode: PNode;
  I: SizeInt;
begin
  Result := 0;
  if Count > 0 then
    for I := 0 to Pred(System.Length(FList)) do
      begin
        CurrNode := FList[I];
        PrevNode := nil;
        while CurrNode <> nil do
          begin
            NextNode := CurrNode^.Next;
            if aTest(@CurrNode^.Data) then
              begin
                if PrevNode <> nil then
                  PrevNode^.Next := NextNode
                else
                  FList[I] := NextNode;
                if aOnRemove <> nil then
                  aOnRemove(@CurrNode^.Data);
                DisposeNode(CurrNode);
                Inc(Result);
              end
            else
              PrevNode := CurrNode;
            CurrNode := NextNode;
          end;
      end;
end;

{ TGHashTableLP.TEnumerator }

function TGHashTableLP.TEnumerator.GetCurrent: PEntry;
begin
  Result := @FList[FCurrIndex].Data;
end;

constructor TGHashTableLP.TEnumerator.Create(constref aList: TNodeList);
begin
  FList := Pointer(aList);
  FLastIndex := System.High(aList);
  FCurrIndex := NULL_INDEX;
end;

function TGHashTableLP.TEnumerator.MoveNext: Boolean;
begin
  repeat
    if FCurrIndex >= FLastIndex then
      exit(False);
    Inc(FCurrIndex);
    Result := FList[FCurrIndex].Hash <> 0;
  until Result;
end;

procedure TGHashTableLP.TEnumerator.Reset;
begin
  FCurrIndex := NULL_INDEX;
end;

{ TGHashTableLP.TRemovableEnumerator }

function TGHashTableLP.TRemovableEnumerator.GetCurrent: PEntry;
begin
  Result := FEnum.Current;
end;

constructor TGHashTableLP.TRemovableEnumerator.Create(aTable: TGHashTableLP);
begin
  FTable := aTable;
  FEnum := aTable.GetEnumerator;
end;

function TGHashTableLP.TRemovableEnumerator.MoveNext: Boolean;
begin
  Result := FEnum.MoveNext;
end;

procedure TGHashTableLP.TRemovableEnumerator.RemoveCurrent;
begin
  FTable.DoRemove(FEnum.FCurrIndex);
  Dec(FEnum.FCurrIndex);
end;

procedure TGHashTableLP.TRemovableEnumerator.Reset;
begin
  FEnum.Reset;
end;

{ TGHashTableLP }

function TGHashTableLP.RestrictLoadFactor(aValue: Single): Single;
begin
  Result := Math.Min(Math.Max(aValue, MIN_LOAD_FACTOR), MAX_LOAD_FACTOR);
end;

function TGHashTableLP.GetCapacity: SizeInt;
begin
  Result := System.Length(FList);
end;

procedure TGHashTableLP.UpdateExpandTreshold;
begin
  if GetCapacity < MAX_CAPACITY then
    FExpandTreshold := Trunc(GetCapacity * LoadFactor)
  else
    FExpandTreshold := MAX_CAPACITY;
end;

procedure TGHashTableLP.SetLoadFactor(aValue: Single);
begin
  aValue := RestrictLoadFactor(aValue);
  if aValue <> LoadFactor then
    begin
      FLoadFactor := aValue;
      UpdateExpandTreshold;
      if Count >= ExpandTreshold then
        Expand;
    end;
end;

function TGHashTableLP.GetFillRatio: Single;
var
  c: SizeInt;
begin
  c := GetCapacity;
  if c > 0 then
    Result := Count / c
  else
    Result := 0.0;
end;

function TGHashTableLP.GetTableSize: SizeInt;
begin
  Result := GetCapacity;
end;

procedure TGHashTableLP.AllocList(aCapacity: SizeInt);
begin
  if aCapacity > 0 then
    begin
      aCapacity := Math.Min(aCapacity, MAX_CAPACITY);
      if not IsTwoPower(aCapacity) then
        aCapacity := LGUtils.RoundUpTwoPower(aCapacity);
    end
  else
    aCapacity := DEFAULT_CONTAINER_CAPACITY;
  System.SetLength(FList, aCapacity);
  UpdateExpandTreshold;
end;

procedure TGHashTableLP.Rehash(var aTarget: TNodeList);
var
  h, I, J, Mask: SizeInt;
begin
  if Count > 0 then
    begin
      Mask := System.High(aTarget);
      for I := 0 to System.High(FList) do
        begin
          if FList[I].Hash <> 0 then
            begin
              h := FList[I].Hash and Mask;
              for J := 0 to Mask do
                begin
                  if aTarget[h].Hash = 0 then // -> target node is empty
                    begin
                      TFakeNode(aTarget[h]) := TFakeNode(FList[I]);
                      TFakeNode(FList[I]) := Default(TFakeNode);
                      break;
                    end;
                  h := Succ(h) and Mask;     // probe sequence
                end;
            end;
        end;
    end;
end;

procedure TGHashTableLP.Resize(aNewCapacity: SizeInt);
var
  List: TNodeList;
begin
  System.SetLength(List, aNewCapacity);
  Rehash(List);
  FList := List;
  UpdateExpandTreshold;
end;

procedure TGHashTableLP.Expand;
var
  NewCapacity, OldCapacity: SizeInt;
begin
  OldCapacity := GetCapacity;
  if OldCapacity > 0 then
    begin
      NewCapacity := Math.Min(MAX_CAPACITY, OldCapacity shl 1);
      if NewCapacity > OldCapacity then
        Resize(NewCapacity);
    end
  else
    AllocList(DEFAULT_CONTAINER_CAPACITY);
end;

function TGHashTableLP.DoFind(constref aKey: TKey; aKeyHash: SizeInt): SizeInt;
var
  I, Pos, h, Mask: SizeInt;
begin
  Mask := System.High(FList);
  aKeyHash := aKeyHash or USED_FLAG;
  Result := SLOT_NOT_FOUND;
  Pos := aKeyHash and Mask;
  for I := 0 to Mask do
    begin
      h := FList[Pos].Hash;
      if h = 0 then               // node empty => key not found
        exit(not Pos)
      else
        if (h = aKeyHash) and TEqRel.Equal(FList[Pos].Data.Key, aKey) then
          exit(Pos);              // key found
      Pos := Succ(Pos) and Mask;  // probe sequence
    end;
end;

procedure TGHashTableLP.DoRemove(aIndex: SizeInt);
var
  I, h, Gap, Mask: SizeInt;
begin
  Mask := System.High(FList);
  FList[aIndex].Hash := 0;
  FList[aIndex].Data := Default(TEntry);
  Gap := aIndex;
  aIndex := Succ(aIndex) and Mask;
  Dec(FCount);
  for I := 0 to Mask do
    begin
      h := FList[aIndex].Hash;
      if h <> 0 then
        begin
          h := h and Mask;
          if (h <> aIndex) and (Succ(aIndex - h + Mask) and Mask >= Succ(aIndex - Gap + Mask) and Mask) then
            begin
              TFakeNode(FList[Gap]) := TFakeNode(FList[aIndex]);
              TFakeNode(FList[aIndex]) := Default(TFakeNode);
              Gap := aIndex;
            end;
          aIndex := Succ(aIndex) and Mask;
        end
      else
        break;
    end;
end;

class function TGHashTableLP.EstimateCapacity(aCount: SizeInt; aLoadFactor: Single): SizeInt;
begin
  if aCount > 0 then
    Result := LGUtils.RoundUpTwoPower(Math.Min(Ceil64(Double(aCount) / aLoadFactor), MAX_CAPACITY))
  else
    Result := DEFAULT_CONTAINER_CAPACITY;
end;

class constructor TGHashTableLP.Init;
begin
  MAX_CAPACITY := LGUtils.RoundUpTwoPower(MAX_CAPACITY);
end;

class function TGHashTableLP.DefaultLoadFactor: Single;
begin
  Result := DEFAULT_LOAD_FACTOR;
end;

class function TGHashTableLP.MaxLoadFactor: Single;
begin
  Result := MAX_LOAD_FACTOR;
end;

class function TGHashTableLP.MinLoadFactor: Single;
begin
  Result := MIN_LOAD_FACTOR;
end;

constructor TGHashTableLP.CreateEmpty;
begin
  FLoadFactor := DefaultLoadFactor;
end;

constructor TGHashTableLP.CreateEmpty(aLoadFactor: Single);
begin
  FLoadFactor := RestrictLoadFactor(aLoadFactor);
end;

constructor TGHashTableLP.Create;
begin
  FLoadFactor := DefaultLoadFactor;
  AllocList(DEFAULT_CONTAINER_CAPACITY);
end;

constructor TGHashTableLP.Create(aCapacity: SizeInt);
begin
  FLoadFactor := DefaultLoadFactor;
  AllocList(EstimateCapacity(aCapacity, LoadFactor));
end;

constructor TGHashTableLP.Create(aLoadFactor: Single);
begin
  FLoadFactor := RestrictLoadFactor(aLoadFactor);
  AllocList(DEFAULT_CONTAINER_CAPACITY);
end;

constructor TGHashTableLP.Create(aCapacity: SizeInt; aLoadFactor: Single);
begin
  FLoadFactor := RestrictLoadFactor(aLoadFactor);
  AllocList(EstimateCapacity(aCapacity, LoadFactor));
end;

function TGHashTableLP.GetEnumerator: TEnumerator;
begin
  Result := TEnumerator.Create(FList);
end;

function TGHashTableLP.GetRemovableEnumerator: TRemovableEnumerator;
begin
  Result := TRemovableEnumerator.Create(Self);
end;

procedure TGHashTableLP.Clear;
begin
  FList := nil;
  FCount := 0;
  FExpandTreshold := 0;
end;

procedure TGHashTableLP.EnsureCapacity(aValue: SizeInt);
var
  NewCapacity: SizeInt;
begin
  if aValue <= ExpandTreshold then
    exit;
  if aValue <= MAX_CAPACITY then
    begin
      NewCapacity := EstimateCapacity(aValue, LoadFactor);
      if NewCapacity <> Capacity then
        Resize(NewCapacity);
    end
  else
    raise ELGCapacityExceed.CreateFmt(SEClassCapacityExceedFmt, [ClassName, aValue]);
end;

procedure TGHashTableLP.TrimToFit;
var
  NewCapacity: SizeInt;
begin
  if Count > 0 then
    begin
      NewCapacity := EstimateCapacity(Count, LoadFactor);
      if NewCapacity < GetCapacity then
        Resize(NewCapacity);
    end
  else
    Clear;
end;

function TGHashTableLP.FindOrAdd(constref aKey: TKey; out e: PEntry; out aPos: SizeInt): Boolean;
var
  h: SizeInt;
begin
  if FList = nil then
    AllocList(DEFAULT_CONTAINER_CAPACITY);
  h := TEqRel.HashCode(aKey);
  aPos := DoFind(aKey, h);
  Result := aPos >= 0; // key found?
  if not Result then   // key not found, will add new slot
    begin
      if Count >= ExpandTreshold then
        begin
          Expand;
          aPos := DoFind(aKey, h);
        end;
      if aPos <> SLOT_NOT_FOUND then
        begin
          aPos := not aPos;
          FList[aPos].Hash := h or USED_FLAG;
          Inc(FCount);
        end
      else
        raise ELGCapacityExceed.CreateFmt(SEClassCapacityExceedFmt, [ClassName, Succ(Count)]);
    end;
  e := @FList[aPos].Data;
end;

function TGHashTableLP.Find(constref aKey: TKey; out aPos: SizeInt): PEntry;
begin
  Result := nil;
  if Count > 0 then
    begin
      aPos := DoFind(aKey, TEqRel.HashCode(aKey));
      if aPos >= 0 then
        Result := @FList[aPos].Data;
    end;
end;

function TGHashTableLP.Remove(constref aKey: TKey): Boolean;
var
  Pos: SizeInt;
begin
  if Count > 0 then
    begin
      Pos := DoFind(aKey, TEqRel.HashCode(aKey));
      Result := Pos >= 0;
      if Result then
        DoRemove(Pos);
    end
  else
    Result := False;
end;

procedure TGHashTableLP.RemoveAt(aPos: SizeInt);
begin
  if (aPos >= 0) and (aPos <= System.High(FList)) then
    DoRemove(aPos);
end;

{ TGLiteHashTableLP.TEnumerator }

function TGLiteHashTableLP.TEnumerator.GetCurrent: PEntry;
begin
  Result := @FList[FCurrIndex].Data;
end;

constructor TGLiteHashTableLP.TEnumerator.Create(constref aList: TNodeList);
begin
  FList := Pointer(aList);
  FLastIndex := System.High(aList);
  FCurrIndex := NULL_INDEX;
end;

function TGLiteHashTableLP.TEnumerator.MoveNext: Boolean;
begin
  repeat
    if FCurrIndex >= FLastIndex then
      exit(False);
    Inc(FCurrIndex);
    Result := FList[FCurrIndex].Hash <> 0;
  until Result;
end;

procedure TGLiteHashTableLP.TEnumerator.Reset;
begin
  FCurrIndex := NULL_INDEX;
end;

{ TGLiteHashTableLP.TRemovableEnumerator }

function TGLiteHashTableLP.TRemovableEnumerator.GetCurrent: PEntry;
begin
  Result := FEnum.Current;
end;

constructor TGLiteHashTableLP.TRemovableEnumerator.Create(aTable: PLiteHashTableLP);
begin
  FTable := aTable;
  FEnum := aTable^.GetEnumerator;
end;

function TGLiteHashTableLP.TRemovableEnumerator.MoveNext: Boolean;
begin
  Result := FEnum.MoveNext;
end;

procedure TGLiteHashTableLP.TRemovableEnumerator.RemoveCurrent;
begin
  FTable^.DoRemove(FEnum.FCurrIndex);
  Dec(FEnum.FCurrIndex);
end;

procedure TGLiteHashTableLP.TRemovableEnumerator.Reset;
begin
  FEnum.Reset;
end;

{ TGLiteHashTableLP }

function TGLiteHashTableLP.RestrictLoadFactor(aValue: Single): Single;
begin
  Result := Math.Min(Math.Max(aValue, MIN_LOAD_FACTOR), MAX_LOAD_FACTOR);
end;

procedure TGLiteHashTableLP.UpdateExpandTreshold;
begin
  if Capacity < MAX_CAPACITY then
    FExpandTreshold := Trunc(Capacity * LoadFactor)
  else
    FExpandTreshold := MAX_CAPACITY;
end;

procedure TGLiteHashTableLP.SetLoadFactor(aValue: Single);
begin
  aValue := RestrictLoadFactor(aValue);
  if aValue <> LoadFactor then
    begin
      FLoadFactor := aValue;
      UpdateExpandTreshold;
      if Count >= ExpandTreshold then
        Expand;
    end;
end;

function TGLiteHashTableLP.GetCapacity: SizeInt;
begin
  Result := System.Length(FList);
end;

function TGLiteHashTableLP.GetFillRatio: Single;
var
  sz: SizeInt;
begin
  sz := Capacity;
  if sz > 0 then
    Result := Count / sz
  else
    Result := 0.0;
end;

procedure TGLiteHashTableLP.AllocList(aCapacity: SizeInt);
begin
  if aCapacity > 0 then
    begin
      aCapacity := Math.Min(aCapacity, MAX_CAPACITY);
      if not LGUtils.IsTwoPower(aCapacity) then
        aCapacity := LGUtils.RoundUpTwoPower(aCapacity);
    end
  else
    aCapacity := DEFAULT_CONTAINER_CAPACITY;
  System.SetLength(FList, aCapacity);
  UpdateExpandTreshold;
end;

procedure TGLiteHashTableLP.Rehash(var aTarget: TNodeList);
var
  h, I, J, Mask: SizeInt;
begin
  if Count > 0 then
    begin
      Mask := System.High(aTarget);
      for I := 0 to System.High(FList) do
        begin
          if FList[I].Hash <> 0 then
            begin
              h := FList[I].Hash and Mask;
              for J := 0 to Mask do
                begin
                  if aTarget[h].Hash = 0 then // -> target node is empty
                    begin
                      TFakeNode(aTarget[h]) := TFakeNode(FList[I]);
                      TFakeNode(FList[I]) := Default(TFakeNode);
                      break;
                    end;
                  h := Succ(h) and Mask;     // probe sequence
                end;
            end;
        end;
    end;
end;

procedure TGLiteHashTableLP.Resize(aNewCapacity: SizeInt);
var
  List: TNodeList;
begin
  System.SetLength(List, aNewCapacity);
  Rehash(List);
  FList := List;
  UpdateExpandTreshold;
end;

procedure TGLiteHashTableLP.Expand;
var
  NewCapacity, OldCapacity: SizeInt;
begin
  OldCapacity := Capacity;
  if OldCapacity > 0 then
    begin
      NewCapacity := Math.Min(MAX_CAPACITY, OldCapacity shl 1);
      if NewCapacity > OldCapacity then
        Resize(NewCapacity);
    end
  else
    AllocList(DEFAULT_CONTAINER_CAPACITY);
end;

function TGLiteHashTableLP.DoFind(constref aKey: TKey; aKeyHash: SizeInt): SizeInt;
var
  I, Pos, h, Mask: SizeInt;
begin
  Mask := System.High(FList);
  aKeyHash := aKeyHash or USED_FLAG;
  Result := SLOT_NOT_FOUND;
  Pos := aKeyHash and Mask;
  for I := 0 to Mask do
    begin
      h := FList[Pos].Hash;
      if h = 0 then               // node empty => key not found
        exit(not Pos)
      else
        if (h = aKeyHash) and TEqRel.Equal(FList[Pos].Data.Key, aKey) then
          exit(Pos);              // key found
      Pos := Succ(Pos) and Mask;  // probe sequence
    end;
end;

procedure TGLiteHashTableLP.DoRemove(aIndex: SizeInt);
var
  I, h, Gap, Mask: SizeInt;
begin
  Mask := System.High(FList);
  FList[aIndex].Hash := 0;
  FList[aIndex].Data := Default(TEntry);
  Gap := aIndex;
  aIndex := Succ(aIndex) and Mask;
  Dec(FCount);
  for I := 0 to Mask do
    begin
      h := FList[aIndex].Hash;
      if h <> 0 then
        begin
          h := h and Mask;
          if (h <> aIndex) and (Succ(aIndex - h + Mask) and Mask >= Succ(aIndex - Gap + Mask) and Mask) then
            begin
              TFakeNode(FList[Gap]) := TFakeNode(FList[aIndex]);
              TFakeNode(FList[aIndex]) := Default(TFakeNode);
              Gap := aIndex;
            end;
          aIndex := Succ(aIndex) and Mask;
        end
      else
        break;
    end;
end;

class function TGLiteHashTableLP.EstimateCapacity(aCount: SizeInt; aLoadFactor: Single): SizeInt;
begin
  if aCount > 0 then
    Result := LGUtils.RoundUpTwoPower(Math.Min(Ceil64(Double(aCount) / aLoadFactor), MAX_CAPACITY))
  else
    Result := DEFAULT_CONTAINER_CAPACITY;
end;

class constructor TGLiteHashTableLP.Init;
begin
  MAX_CAPACITY := LGUtils.RoundUpTwoPower(MAX_CAPACITY);
end;

class operator TGLiteHashTableLP.Initialize(var ht: TGLiteHashTableLP);
begin
  ht.FCount := 0;
  ht.FExpandTreshold := 0;
  ht.FLoadFactor := DEFAULT_LOAD_FACTOR;
end;

class operator TGLiteHashTableLP.Copy(constref aSrc: TGLiteHashTableLP; var aDst: TGLiteHashTableLP);
begin
  if @aSrc <> @aDst then
    begin
      aDst.FList := System.Copy(aSrc.FList, 0, System.Length(aSrc.FList));
      aDst.FCount := aSrc.Count;
      aDst.FExpandTreshold := aSrc.ExpandTreshold;
      aDst.FLoadFactor := aSrc.LoadFactor;
    end;
end;

function TGLiteHashTableLP.GetEnumerator: TEnumerator;
begin
  Result := TEnumerator.Create(FList);
end;

function TGLiteHashTableLP.GetRemovableEnumerator: TRemovableEnumerator;
begin
  Result := TRemovableEnumerator.Create(@Self);
end;

procedure TGLiteHashTableLP.Clear;
begin
  FList := nil;
  FCount := 0;
  FExpandTreshold := 0;
end;

procedure TGLiteHashTableLP.EnsureCapacity(aValue: SizeInt);
var
  NewCapacity: SizeInt;
begin
  if aValue <= ExpandTreshold then
    exit;
  if aValue <= MAX_CAPACITY then
    begin
      NewCapacity := EstimateCapacity(aValue, LoadFactor);
      if NewCapacity <> Capacity then
        Resize(NewCapacity);
    end
  else
    raise ELGCapacityExceed.CreateFmt(SECapacityExceedFmt, [aValue]);
end;

procedure TGLiteHashTableLP.TrimToFit;
var
  NewCapacity: SizeInt;
begin
  if Count > 0 then
    begin
      NewCapacity := EstimateCapacity(Count, LoadFactor);
      if NewCapacity < Capacity then
        Resize(NewCapacity);
    end
  else
    Clear;
end;

function TGLiteHashTableLP.FindOrAdd(constref aKey: TKey; out e: PEntry; out aPos: SizeInt): Boolean;
var
  h: SizeInt;
begin
  if FList = nil then
    AllocList(DEFAULT_CONTAINER_CAPACITY);
  h := TEqRel.HashCode(aKey);
  aPos := DoFind(aKey, h);
  Result := aPos >= 0; // key found?
  if not Result then   // key not found, will add new slot
    begin
      if Count >= ExpandTreshold then
        begin
          Expand;
          aPos := DoFind(aKey, h);
        end;
      if aPos <> SLOT_NOT_FOUND then
        begin
          aPos := not aPos;
          FList[aPos].Hash := h or USED_FLAG;
          Inc(FCount);
        end
      else
        raise ELGCapacityExceed.CreateFmt(SECapacityExceedFmt, [Succ(Count)]);
    end;
  e := @FList[aPos].Data;
end;

function TGLiteHashTableLP.Find(constref aKey: TKey; out aPos: SizeInt): PEntry;
begin
  Result := nil;
  if Count > 0 then
    begin
      aPos := DoFind(aKey, TEqRel.HashCode(aKey));
      if aPos >= 0 then
        Result := @FList[aPos].Data;
    end;
end;

function TGLiteHashTableLP.Remove(constref aKey: TKey): Boolean;
var
  Pos: SizeInt;
begin
  if Count > 0 then
    begin
      Pos := DoFind(aKey, TEqRel.HashCode(aKey));
      if Pos >= 0 then
        begin
          DoRemove(Pos);
          exit(True);
        end;
    end;
  Result := False;
end;

procedure TGLiteHashTableLP.RemoveAt(aPos: SizeInt);
begin
  if (aPos >= 0) and (aPos <= System.High(FList)) then
    DoRemove(aPos);
end;

{ TGLiteChainHashTable }

function TGLiteChainHashTable.GetCapacity: SizeInt;
begin
  Result := System.Length(FNodeList);
end;

function TGLiteChainHashTable.GetNodeList: PNode;
begin
  Result := Pointer(FNodeList);
end;

procedure TGLiteChainHashTable.InitialAlloc;
begin
  System.SetLength(FNodeList, DEFAULT_CONTAINER_CAPACITY);
  System.SetLength(FChainList, DEFAULT_CONTAINER_CAPACITY);
  System.FillChar(Pointer(FChainList)^, DEFAULT_CONTAINER_CAPACITY * SizeOf(SizeInt), $ff);
end;

procedure TGLiteChainHashTable.Rehash;
var
  I, J, Mask: SizeInt;
begin
  Mask := System.High(FNodeList);
  System.FillChar(Pointer(FChainList)^, Succ(Mask) * SizeOf(SizeInt), $ff);
  for I := 0 to Pred(Count) do
    begin
      J := FNodeList[I].Hash and Mask;
      FNodeList[I].Next := FChainList[J];
      FChainList[J] := I;
    end;
end;

procedure TGLiteChainHashTable.Resize(aNewCapacity: SizeInt);
begin
  System.SetLength(FNodeList, aNewCapacity);
  System.SetLength(FChainList, aNewCapacity);
  Rehash;
end;

procedure TGLiteChainHashTable.Expand;
begin
  if Capacity > 0 then
    Resize(Capacity shl 1)
  else
    InitialAlloc;
end;

procedure TGLiteChainHashTable.RemoveFromChain(aIndex: SizeInt);
var
  I, Curr, Prev: SizeInt;
begin
  I := FNodeList[aIndex].Hash and System.High(FNodeList);
  Curr := FChainList[I];
  Prev := NULL_INDEX;
  while Curr <> NULL_INDEX do
    begin
      if Curr = aIndex then
        begin
          if Prev <> NULL_INDEX then
            FNodeList[Prev].Next := FNodeList[Curr].Next
          else
            FChainList[I] := FNodeList[Curr].Next;
          exit;
        end;
      Prev := Curr;
      Curr := FNodeList[Curr].Next;
    end;
end;

procedure TGLiteChainHashTable.FixChain(aOldIndex, aNewIndex: SizeInt);
var
  I: SizeInt;
begin
  I := FNodeList[aNewIndex].Hash and System.High(FNodeList);
  if FChainList[I] <> aOldIndex then
    begin
      I := FChainList[I];
      repeat
        if FNodeList[I].Next = aOldIndex then
          begin
            FNodeList[I].Next := aNewIndex;
            exit;
          end;
        I := FNodeList[I].Next;
      until False
    end
  else
    FChainList[I] := aNewIndex;
end;

function TGLiteChainHashTable.DoFind(constref aKey: TKey; aHash: SizeInt; out aPos: TSearchResult): Boolean;
var
  I: SizeInt;
begin
  I := FChainList[aHash and System.High(FNodeList)];
  aPos.PrevIndex := NULL_INDEX;
  while I <> NULL_INDEX do
    begin
      if (FNodeList[I].Hash = aHash) and TKeyEqRel.Equal(FNodeList[I].Data.Key, aKey) then
        begin
          aPos.Index := I;
          exit(True);
        end;
      aPos.PrevIndex := I;
      I := FNodeList[I].Next;
    end;
  Result := False;
end;

function TGLiteChainHashTable.DoAdd(aKeyHash: SizeInt): SizeInt;
var
  I: SizeInt;
begin
  Result := Count;
  I := aKeyHash and System.High(FNodeList);
  FNodeList[Result].Hash := aKeyHash;
  FNodeList[Result].Next := FChainList[I];
  FChainList[I] := Result;
  Inc(FCount);
end;

procedure TGLiteChainHashTable.DoRemove(constref aPos: TSearchResult);
begin
  if aPos.PrevIndex <> NULL_INDEX then  //is not head of chain
    FNodeList[aPos.PrevIndex].Next := FNodeList[aPos.Index].Next
  else
    FChainList[FNodeList[aPos.Index].Hash and Pred(Capacity)] := FNodeList[aPos.Index].Next;
  FNodeList[aPos.Index].Data := Default(TEntry);
  Dec(FCount);
  if aPos.Index < Count then
    begin
      //System.Move(FNodeList[Count], FNodeList[aPos.Index], SizeOf(TNode));
      FNodeList[aPos.Index] := FNodeList[Count];
      System.FillChar(FNodeList[Count], SizeOf(TNode), 0);
      FixChain(Count, aPos.Index);
    end;
end;

procedure TGLiteChainHashTable.DoRemoveIndex(aIndex: SizeInt);
begin
  RemoveFromChain(aIndex);
  FNodeList[aIndex].Data := Default(TEntry);
  Dec(FCount);
  if aIndex < Count then
    begin
      //System.Move(FNodeList[Count], FNodeList[aIndex], SizeOf(TNode));
      FNodeList[aIndex] := FNodeList[Count];
      System.FillChar(FNodeList[Count], SizeOf(TNode), 0);
      FixChain(Count, aIndex);
    end;
end;

class operator TGLiteChainHashTable.Initialize(var ht: TGLiteChainHashTable);
begin
  ht.FCount := 0;
end;

class operator TGLiteChainHashTable.Copy(constref aSrc: TGLiteChainHashTable; var aDst: TGLiteChainHashTable);
begin
  if @aSrc <> @aDst then
    begin
      aDst.FNodeList := System.Copy(aSrc.FNodeList);
      aDst.FChainList := System.Copy(aSrc.FChainList);
      aDst.FCount := aSrc.Count;
    end;
end;

procedure TGLiteChainHashTable.Clear;
begin
  FNodeList := nil;
  FChainList := nil;
  FCount := 0;
end;

procedure TGLiteChainHashTable.EnsureCapacity(aValue: SizeInt);
begin
  if aValue <= Capacity then
    exit;
  if aValue <= DEFAULT_CONTAINER_CAPACITY then
    aValue := DEFAULT_CONTAINER_CAPACITY
  else
    if aValue < MAX_CONTAINER_SIZE div SizeOf(TNode) then
      aValue := LGUtils.RoundUpTwoPower(aValue)
    else
      raise ELGCapacityExceed.CreateFmt(SECapacityExceedFmt, [aValue]);
  Resize(aValue);
end;

procedure TGLiteChainHashTable.TrimToFit;
var
  NewCapacity: SizeInt;
begin
  if Count > 0 then
    begin
      NewCapacity := LGUtils.RoundUpTwoPower(Count);
      if NewCapacity < Capacity then
        Resize(NewCapacity);
    end
  else
    Clear;
end;

function TGLiteChainHashTable.FindOrAdd(constref aKey: TKey; out e: PEntry; out aIndex: SizeInt): Boolean;
var
  h: SizeInt;
  sr: TSearchResult;
begin
  h := TKeyEqRel.HashCode(aKey);
  sr.Index := NULL_INDEX;
  if Count > 0 then
    Result := DoFind(aKey, h, sr)
  else
    Result := False;
  if not Result then          // key not found
    begin
      if Count = Capacity then
        Expand;
      sr.Index := DoAdd(h);
    end;
  aIndex := sr.Index;
  e := @FNodeList[sr.Index].Data;
end;

function TGLiteChainHashTable.Find(constref aKey: TKey; out aIndex: SizeInt): PEntry;
var
  sr: TSearchResult;
begin
  sr.Index := NULL_INDEX;
  if (Count > 0) and DoFind(aKey, TKeyEqRel.HashCode(aKey), sr) then
    Result := @FNodeList[sr.Index].Data
  else
    Result := nil;
  aIndex := sr.Index;
end;

function TGLiteChainHashTable.Remove(constref aKey: TKey): Boolean;
var
  p: TSearchResult;
begin
  if Count > 0 then
    begin
      Result := DoFind(aKey, TKeyEqRel.HashCode(aKey), p);
      if Result then
        DoRemove(p);
    end
  else
    Result := False;
end;

procedure TGLiteChainHashTable.RemoveIndex(aIndex: SizeInt);
begin
  if (aIndex >= 0) and (aIndex < Count) then
    DoRemoveIndex(aIndex)
  else
    raise ELGListError.CreateFmt(SEIndexOutOfBoundsFmt, [aIndex]);
end;

{ TGLiteIntHashTable.TEnumerator }

function TGLiteIntHashTable.TEnumerator.GetCurrent: PEntry;
begin
  Result := @FList[FCurrIndex].Data;
end;

function TGLiteIntHashTable.TEnumerator.MoveNext: Boolean;
begin
  repeat
    if FCurrIndex >= FLastIndex then
      exit(False);
    Inc(FCurrIndex);
    Result := FList[FCurrIndex].Hash <> 0;
  until Result;
end;

procedure TGLiteIntHashTable.TEnumerator.Reset;
begin
  FCurrIndex := NULL_INDEX;
end;

{ TGLiteIntHashTable.TRemovableEnumerator }

function TGLiteIntHashTable.TRemovableEnumerator.GetCurrent: PEntry;
begin
  Result := FEnum.Current;
end;

constructor TGLiteIntHashTable.TRemovableEnumerator.Create(aTable: PHashTable);
begin
  FTable := aTable;
  FEnum := aTable^.GetEnumerator;
end;

function TGLiteIntHashTable.TRemovableEnumerator.MoveNext: Boolean;
begin
  Result := FEnum.MoveNext;
end;

procedure TGLiteIntHashTable.TRemovableEnumerator.RemoveCurrent;
begin
  FTable^.DoRemove(FEnum.FCurrIndex);
  Dec(FEnum.FCurrIndex);
end;

procedure TGLiteIntHashTable.TRemovableEnumerator.Reset;
begin
  FEnum.Reset;
end;

{ TGLiteIntHashTable }

function TGLiteIntHashTable.GetExpandTreshold: SizeInt;
begin
  Result := System.Length(FList) shr 1;
end;

function TGLiteIntHashTable.GetCapacity: SizeInt;
begin
  Result := System.Length(FList);
end;

procedure TGLiteIntHashTable.Rehash(var aTarget: TNodeList);
var
  h, I, J, Mask: SizeInt;
begin
  if Count > 0 then
    begin
      Mask := System.High(aTarget);
      for I := 0 to System.High(FList) do
        begin
          if FList[I].Hash <> 0 then
            begin
              h := FList[I].Hash shr FShift;
              for J := 0 to Mask do
                begin
                  if aTarget[h].Hash = 0 then // -> target node is empty
                    begin
                      TFakeNode(aTarget[h]) := TFakeNode(FList[I]);
                      TFakeNode(FList[I]) := Default(TFakeNode);
                      break;
                    end;
                  h := Succ(h) and Mask;     // probe sequence
                end;
            end;
        end;
    end;
end;

procedure TGLiteIntHashTable.Resize(aNewCapacity: SizeInt);
var
  List: TNodeList;
begin
  System.SetLength(List, aNewCapacity);
{$IF DEFINED(CPU64)}
  FShift := 64 - BsrQWord(QWord(aNewCapacity));
{$ELSEIF DEFINED(CPU32)}
  FShift := 32 - BsrDWord(DWord(aNewCapacity));
{$ELSE}
  FShift := 16 - BsrWord(Word(aNewCapacity));
{$ENDIF}
  Rehash(List);
  FList := List;
end;

procedure TGLiteIntHashTable.Expand;
var
  NewCapacity, OldCapacity: SizeInt;
begin
  OldCapacity := GetCapacity;
  if OldCapacity > 0 then
    begin
      NewCapacity := Math.Min(MAX_CAPACITY, OldCapacity shl 1);
      if NewCapacity > OldCapacity then
        Resize(NewCapacity);
    end
  else
    Resize(DEFAULT_CONTAINER_CAPACITY);
end;

function TGLiteIntHashTable.DoFind(aKey: TKey; aKeyHash: SizeInt): SizeInt;
var
  I, Pos, Mask: SizeInt;
begin
  Mask := System.High(FList);
  Result := SLOT_NOT_FOUND;
  Pos := aKeyHash shr FShift;
  for I := 0 to Mask do
    begin
      if FList[Pos].Hash = 0 then // node empty => key not found
        exit(not Pos)
      else
        if FList[Pos].Data.Key = aKey then
          exit(Pos);              // key found
      Pos := Succ(Pos) and Mask;  // probe sequence
    end;
end;

procedure TGLiteIntHashTable.DoRemove(aIndex: SizeInt);
var
  h, Gap, Mask: SizeInt;
begin
  Mask := System.High(FList);
  FList[aIndex].Hash := 0;
  FList[aIndex].Data := Default(TEntry);
  Gap := aIndex;
  aIndex := Succ(aIndex) and Mask;
  Dec(FCount);
  repeat
    if FList[aIndex].Hash = 0 then
      break;
    h := FList[aIndex].Hash shr FShift;
    if (h <> aIndex) and (Succ(aIndex - h + Mask) and Mask >= Succ(aIndex - Gap + Mask) and Mask) then
      begin
        TFakeNode(FList[Gap]) := TFakeNode(FList[aIndex]);
        TFakeNode(FList[aIndex]) := Default(TFakeNode);
        Gap := aIndex;
      end;
    aIndex := Succ(aIndex) and Mask;
  until False;
end;

class function TGLiteIntHashTable.HashCode(aValue: TKey): SizeInt;
begin
{$IF DEFINED(CPU64)}
  Result := SizeInt(aValue) * SizeInt($9e3779b97f4a7c15);
{$ELSEIF DEFINED(CPU32)}
  Result := SizeInt(aValue) * SizeInt($9e3779b9);
{$ELSE}
  Result := SizeInt(aValue) * SizeInt($9e37);
{$ENDIF}
end;

class constructor TGLiteIntHashTable.Init;
begin
  MAX_CAPACITY := LGUtils.RoundUpTwoPower(MAX_CAPACITY);
end;

class operator TGLiteIntHashTable.Initialize(var ht: TGLiteIntHashTable);
begin
  ht.FCount := 0;
end;

class operator TGLiteIntHashTable.Copy(constref aSrc: TGLiteIntHashTable; var aDst: TGLiteIntHashTable);
begin
  aDst.FList := System.Copy(aSrc.FList);
  aDst.FCount := aSrc.Count;
  aDst.FShift := aSrc.FShift;
end;

function TGLiteIntHashTable.GetEnumerator: TEnumerator;
begin
  Result.FList := Pointer(FList);
  Result.FLastIndex := System.High(FList);
  Result.FCurrIndex := NULL_INDEX;
end;

function TGLiteIntHashTable.GetRemovableEnumerator: TRemovableEnumerator;
begin
  Result := TRemovableEnumerator.Create(@Self);
end;

procedure TGLiteIntHashTable.Clear;
begin
  FList := nil;
  FCount := 0;
end;

procedure TGLiteIntHashTable.MakeEmpty;
var
  I: SizeInt;
begin
  for I := 0 to Pred(Capacity) do
    FList[I] := Default(TNode);
  FCount := 0;
end;

procedure TGLiteIntHashTable.EnsureCapacity(aValue: SizeInt);
var
  NewCapacity: SizeInt;
begin
  if aValue <= ExpandTreshold then
    exit;
  if aValue <= MAX_CAPACITY then
    begin
      if aValue <= MAX_CAPACITY shr 1 then
        NewCapacity := LGUtils.RoundUpTwoPower(aValue) shl 1
      else
        NewCapacity := MAX_CAPACITY;
      if NewCapacity <> Capacity then
        Resize(NewCapacity);
    end
  else
    raise ELGCapacityExceed.CreateFmt(SECapacityExceedFmt, [aValue]);
end;

procedure TGLiteIntHashTable.TrimToFit;
var
  NewCapacity: SizeInt;
begin
  if Count > 0 then
    begin
      NewCapacity := LGUtils.RoundUpTwoPower(Count shl 1);
      if NewCapacity < Capacity then
        Resize(NewCapacity);
    end
  else
    Clear;
end;

function TGLiteIntHashTable.Contains(aKey: TKey): Boolean;
begin
  Result := Find(aKey) <> nil;
end;

function TGLiteIntHashTable.FindOrAdd(aKey: TKey; out e: PEntry; out aPos: SizeInt): Boolean;
var
  Hash: SizeInt;
begin
  if FList = nil then
    Resize(DEFAULT_CONTAINER_CAPACITY);
  Hash := HashCode(aKey) or USED_FLAG;
  aPos := DoFind(aKey, Hash);
  Result := aPos >= 0;
  if not Result then
    begin
      if Count >= ExpandTreshold then
        begin
          Expand;
          aPos := DoFind(aKey, Hash);
        end;
      if aPos <> SLOT_NOT_FOUND then
        begin
          aPos := not aPos;
          FList[aPos].Hash := Hash;
          Inc(FCount);
        end
      else
        raise ELGCapacityExceed.CreateFmt(SECapacityExceedFmt, [Succ(Count)]);
    end;
  e := @FList[aPos].Data;
end;

function TGLiteIntHashTable.Find(aKey: TKey): PEntry;
var
  Pos: SizeInt;
begin
  Result := nil;
  if Count > 0 then
    begin
      Pos := DoFind(aKey, HashCode(aKey));
      if Pos >= 0 then
        Result := @FList[Pos].Data;
    end;
end;

function TGLiteIntHashTable.FindFirstKey(out aKey: TKey): Boolean;
var
  I: SizeInt;
begin
  if Count > 0 then
    for I := 0 to Pred(Capacity) do
      if FList[I].Hash <> 0 then
        begin
          aKey := FList[I].Data.Key;
          exit(True);
        end;
  Result := False;
end;

function TGLiteIntHashTable.Remove(aKey: TKey): Boolean;
var
  Pos: SizeInt;
begin
  if Count > 0 then
    begin
      Pos := DoFind(aKey, HashCode(aKey));
      Result := Pos >= 0;
      if Result then
        DoRemove(Pos);
    end
  else
    Result := False;
end;

procedure TGLiteIntHashTable.RemoveAt(aPos: SizeInt);
begin
  if (aPos >= 0) and (aPos <= System.High(FList)) then
    DoRemove(aPos);
end;

end.

