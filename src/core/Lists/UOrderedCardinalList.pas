unit UOrderedCardinalList;

interface

uses
  Classes, UCardinalsArray;

type
  TOrderedCardinalList = Class
  private
    FOrderedList : TList;
    FDisabledsCount : Integer;
    FModifiedWhileDisabled : Boolean;
    FOnListChanged: TNotifyEvent;
    Procedure NotifyChanged;
  public
    Constructor Create;
    Destructor Destroy; override;
    Function Add(Value : Cardinal) : Integer;
    Procedure Remove(Value : Cardinal);
    Procedure Clear;
    Function Get(index : Integer) : Cardinal;
    Function Count : Integer;
    Function Find(const Value: Cardinal; var Index: Integer): Boolean;
    Procedure Disable;
    Procedure Enable;
    Property OnListChanged : TNotifyEvent read FOnListChanged write FOnListChanged;
    Procedure CopyFrom(Sender : TOrderedCardinalList);
    Function ToArray : TCardinalsArray;
  End;

implementation

uses
  SysUtils;

{ TOrderedCardinalList }

function TOrderedCardinalList.Add(Value: Cardinal): Integer;
begin
  if Find(Value,Result) then exit
  else begin
    FOrderedList.Insert(Result,TObject(Value));
    NotifyChanged;
  end;
end;

procedure TOrderedCardinalList.Clear;
begin
  FOrderedList.Clear;
  NotifyChanged;
end;

procedure TOrderedCardinalList.CopyFrom(Sender: TOrderedCardinalList);
Var i : Integer;
begin
  if Self=Sender then exit;
  Disable;
  Try
    Clear;
    for I := 0 to Sender.Count - 1 do begin
      Add(Sender.Get(i));
    end;
  Finally
    Enable;
  End;
end;

function TOrderedCardinalList.Count: Integer;
begin
  Result := FOrderedList.Count;
end;

constructor TOrderedCardinalList.Create;
begin
  FOrderedList := TList.Create;
  FDisabledsCount := 0;
  FModifiedWhileDisabled := false;
end;

destructor TOrderedCardinalList.Destroy;
begin
  FOrderedList.Free;
  inherited;
end;

procedure TOrderedCardinalList.Disable;
begin
  inc(FDisabledsCount);
end;

procedure TOrderedCardinalList.Enable;
begin
  if FDisabledsCount<=0 then raise Exception.Create('Dev error. Invalid disabled counter');
  dec(FDisabledsCount);
  if (FDisabledsCount=0) And (FModifiedWhileDisabled) then NotifyChanged;
end;

function TOrderedCardinalList.Find(const Value: Cardinal; var Index: Integer): Boolean;
var L, H, I: Integer;
  C : Int64;
begin
  Result := False;
  L := 0;
  H := FOrderedList.Count - 1;
  while L <= H do
  begin
    I := (L + H) shr 1;
    C := Int64(FOrderedList[I]) - Int64(Value);
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

function TOrderedCardinalList.Get(index: Integer): Cardinal;
begin
  Result := Cardinal(FOrderedList[index]);
end;

procedure TOrderedCardinalList.NotifyChanged;
begin
  if FDisabledsCount>0 then begin
    FModifiedWhileDisabled := true;
    exit;
  end;
  FModifiedWhileDisabled := false;
  if Assigned(FOnListChanged) then FOnListChanged(Self);
end;

procedure TOrderedCardinalList.Remove(Value: Cardinal);
Var i : Integer;
begin
  if Find(Value,i) then begin
    FOrderedList.Delete(i);
    NotifyChanged;
  end;
end;

Function TOrderedCardinalList.ToArray : TCardinalsArray;
var i : integer;
begin
  SetLength(Result, self.Count);
  for i := 0 to self.Count - 1 do
    Result[i] := Self.Get(i);
end;

end.
