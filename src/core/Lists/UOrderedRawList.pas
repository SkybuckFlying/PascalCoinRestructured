unit UOrderedRawList;

interface

uses
  Classes, URawBytes;

type
  // Maintains a TRawBytes (AnsiString) list ordered to quick search withoud duplicates

  { TOrderedRawList }
  TOrderedRawList = Class
  private
    FList : TList;
  public
    Constructor Create;
    Destructor Destroy; Override;
    Procedure Clear;
    Function Add(Const RawData : TRawBytes; tagValue : Integer = 0) : Integer;
    Procedure Remove(Const RawData : TRawBytes);
    Function Count : Integer;
    Function Get(index : Integer) : TRawBytes;
    Procedure Delete(index : Integer);
    procedure SetTag(Const RawData : TRawBytes; newTagValue : Integer);
    function GetTag(Const RawData : TRawBytes) : Integer; overload;
    function GetTag(index : Integer) : Integer; overload;
    Function IndexOf(Const RawData : TRawBytes) : Integer;

    Function Find(const RawData: TRawBytes; var Index: Integer): Boolean;

    Procedure CopyFrom(master : TOrderedRawList);
  End;

implementation

uses
  SysUtils, UBaseType;

{ TOrderedRawList }

Type TRawListData = Record
    RawData : TRawBytes;
    tag : Integer;
  End;
  PRawListData = ^TRawListData;

function TOrderedRawList.Add(const RawData: TRawBytes; tagValue : Integer = 0) : Integer;
Var P : PRawListData;
begin
  if Find(RawData,Result) then begin
    PRawListData(FList[Result])^.tag := tagValue;
  end else begin
    New(P);
    P^.RawData := RawData;
    P^.tag := tagValue;
    FList.Insert(Result,P);
  end;
end;

procedure TOrderedRawList.Remove(const RawData: TRawBytes);
Var i : Integer;
begin
  i := IndexOf(RawData);
  If i>=0 then Delete(i);
end;

procedure TOrderedRawList.Clear;
Var P : PRawListData;
  i : Integer;
begin
  for i := FList.Count - 1 downto 0 do begin
    P := FList[i];
    Dispose(P);
  end;
  FList.Clear;
end;

function TOrderedRawList.Count: Integer;
begin
  Result := FList.Count;
end;

constructor TOrderedRawList.Create;
begin
  FList := TList.Create;
end;

procedure TOrderedRawList.Delete(index: Integer);
Var P : PRawListData;
begin
  P := PRawListData(FList[index]);
  FList.Delete(index);
  Dispose(P);
end;

destructor TOrderedRawList.Destroy;
begin
  Clear;
  FreeAndNil(FList);
  inherited;
end;

function TOrderedRawList.Find(const RawData: TRawBytes; var Index: Integer): Boolean;
var L, H, I: Integer;
  c : Integer;
begin
  Result := False;
  L := 0;
  H := FList.Count - 1;
  while L <= H do
  begin
    I := (L + H) shr 1;
    c := TBaseType.BinStrComp(PRawListData(FList[i])^.RawData,RawData);
    if C < 0 then L := I + 1 else
    begin
      H := I - 1;
      if C = 0 then
      begin
        Result := True;
        L := I;
      end;
    end;
  end;
  Index := L;
end;

function TOrderedRawList.Get(index: Integer): TRawBytes;
begin
  Result := PRawListData(FList[index])^.RawData;
end;

function TOrderedRawList.GetTag(index: Integer): Integer;
begin
  Result := PRawListData(FList[index])^.tag;
end;

function TOrderedRawList.GetTag(const RawData: TRawBytes): Integer;
Var i : Integer;
begin
  if Not Find(RawData,i) then begin
    Result := 0;
  end else begin
    Result := PRawListData(FList[i])^.tag;
  end;
end;

function TOrderedRawList.IndexOf(const RawData: TRawBytes): Integer;
begin
  if Not Find(RawData,Result) then Result := -1;
end;

procedure TOrderedRawList.CopyFrom(master: TOrderedRawList);
Var i : Integer;
begin
  If master=Self then Exit;
  Clear;
  For i:=0 to master.Count-1 do begin
    Add(master.Get(i),master.GetTag(i));
  end;
end;

procedure TOrderedRawList.SetTag(const RawData: TRawBytes; newTagValue: Integer);
begin
  Add(RawData,newTagValue);
end;


end.
