{****************************************************************************
*                                                                           *
*   This file is part of the LGenerics package.                             *
*                                                                           *
*   Copyright(c) 2018 A.Koverdyaev(avk)                                     *
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

type
  TIntSet = record
  private
    FItems: TIntArray;
    FCount: SizeInt;
    procedure Expand; inline;
    function  GetItem(aIndex: SizeInt): SizeInt; inline;
    class operator Initialize(var aList: TIntSet);
  public
  type
    TEnumerator = record
    private
      pCurr,
      pLast: PSizeInt;
      function  GetCurrent: SizeInt; inline;
    public
      function  MoveNext: Boolean; inline;
      property  Current: SizeInt read GetCurrent;
    end;

    procedure InitRange(aRange: SizeInt);
    function  GetEnumerator: TEnumerator; inline;
    function  ToArray: TIntArray; inline;
    procedure Assign(constref aValue: TIntSet);
    procedure AssignArray(constref a: TIntArray);
    procedure AssignList(aList: PAdjList);
    function  IsEmpty: Boolean; inline;
    function  NonEmpty: Boolean; inline;
    procedure MakeEmpty; inline;
    function  FindFirst(out aValue: SizeInt): Boolean;
    function  Contains(aValue: SizeInt): Boolean; inline;
    function  ContainsAny(constref aValue: TIntSet): Boolean;
    function  ContainsAll(constref aValue: TIntSet): Boolean;
    function  Find(aValue: SizeInt): SizeInt;
    function  Add(aValue: SizeInt): Boolean;
    function  Add(constref a: TIntArray): SizeInt;
    function  Join(constref aValue: TIntSet): SizeInt;
    procedure Push(aValue: SizeInt); inline;
    function  Pop: SizeInt; inline;
    function  TryPop(out aValue: SizeInt): Boolean; inline;
    function  Last: SizeInt; inline;
  { preserves the order of the elements }
    procedure Subtract(constref aValue: TIntSet);
    procedure Subtract(PList: PAdjList);
    function  Difference(constref aValue: TIntSet): TIntSet; inline;
  { preserves the order of the elements }
    procedure Intersect(constref aValue: TIntSet);
    function  Intersection(constref aValue: TIntSet): TIntSet; inline;
  { returns the number of elements in the intersection with aValue }
    function  IntersectionCount(constref aValue: TIntSet): SizeInt;
  { returns the number of elements in the intersection with PList }
    function  IntersectionCount(PList: PAdjList): SizeInt;
    function  Remove(aValue: SizeInt): Boolean;
  { preserves the order of the elements }
    procedure Delete(aValue: SizeInt);
    procedure Reverse; inline;
    property  Count: SizeInt read FCount;
    property  Items[aIndex: SizeInt]: SizeInt read GetItem; default;
  end;
  PIntSet = ^TIntSet;

  TSkeleton = record
  private
    FAdjLists: array of TIntSet;
    FEdgeCount: SizeInt;
    FDirected: Boolean;
    function  GetAdjList(aIndex: SizeInt): PIntSet; inline;
    function  GetDegree(aIndex: SizeInt): SizeInt; inline;
    function  GetVertexCount: SizeInt; inline;
  public
    constructor Create(aVertCount: SizeInt; aDirected: Boolean = False);
    constructor Create(constref s: TSkeleton);
    function ContainsEdge(aSrc, aDst: SizeInt): Boolean; inline;
    function AddEdge(aSrc, aDst: SizeInt): Boolean;
    function RemoveEdge(aSrc, aDst: SizeInt): Boolean;
    property VertexCount: SizeInt read GetVertexCount;
    property Directed: Boolean read FDirected;
    property EdgeCount: SizeInt read FEdgeCount;
    property Degree[aIndex: SizeInt]: SizeInt read GetDegree;
    property AdjLists[aIndex: SizeInt]: PIntSet read GetAdjList; default;
  end;
