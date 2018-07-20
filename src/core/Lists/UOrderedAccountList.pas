unit UOrderedAccountList;

interface

uses
  Classes, UAccountKey, UAccount;

type
  TOrderedAccountList = Class
  private
    FList : TList;
  public
    Constructor Create;
    Destructor Destroy; Override;
    Procedure Clear;
    Function Add(Const account : TAccount) : Integer;
    Function Count : Integer;
    Function Get(index : Integer) : TAccount;

    // Skybuck: moved to here to make it accessable to TPCSafeBoxTransaction
    Function Find(const account_number: Cardinal; var Index: Integer): Boolean;

    // Skybuck: property added to make FList accessable to TPCSafeBoxTransaction
    property List : TList read FList;

  End;

implementation

uses
  SysUtils;

{ TOrderedAccountList }

Function TOrderedAccountList.Add(const account: TAccount) : Integer;
Var P : PAccount;
begin
  if Find(account.account,Result) then begin
    PAccount(FList[Result])^ := account;
  end else begin
    New(P);
    P^:=account;
    FList.Insert(Result,P);
  end;
end;

procedure TOrderedAccountList.Clear;
Var i : Integer;
  P : PAccount;
begin
  for I := 0 to FList.Count - 1 do begin
    P := FList[i];
    Dispose(P);
  end;
  FList.Clear;
end;

function TOrderedAccountList.Count: Integer;
begin
  Result := FList.Count;
end;

constructor TOrderedAccountList.Create;
begin
  FList := TList.Create;
end;

destructor TOrderedAccountList.Destroy;
begin
  Clear;
  FreeAndNil(FList);
  inherited;
end;

function TOrderedAccountList.Find(const account_number: Cardinal; var Index: Integer): Boolean;
var L, H, I: Integer;
  C : Int64;
begin
  Result := False;
  L := 0;
  H := FList.Count - 1;
  while L <= H do
  begin
    I := (L + H) shr 1;
    C := Int64(PAccount(FList[I]).account) - Int64(account_number);
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

function TOrderedAccountList.Get(index: Integer): TAccount;
begin
  Result := PAccount(FList.Items[index])^;
end;

end.
