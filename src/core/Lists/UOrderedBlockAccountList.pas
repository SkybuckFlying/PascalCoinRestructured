unit UOrderedBlockAccountList;

interface

uses
  Classes, UBlockAccount;

type
  { TOrderedBlockAccountList }
  TOrderedBlockAccountList = Class
  private
    FMaxBlockNumber : Integer;
    FList : TList;
    Function SaveBlockAccount(Const blockAccount : TBlockAccount; UpdateIfFound : Boolean) : Integer;
  public
    Constructor Create;
    Destructor Destroy; Override;

    Procedure Clear;

    Function AddIfNotExists(Const blockAccount : TBlockAccount) : Integer;
    Function Add(Const blockAccount : TBlockAccount) : Integer;
    Function Count : Integer;
    Function Get(index : Integer) : TBlockAccount;

    // Skybuck: moved to here to make it accessable to TPCSafeBox
    Function Find(const block_number: Cardinal; out Index: Integer): Boolean;

    Function MaxBlockNumber : Integer;
  End;

implementation

uses
  UMemBlockAccount, SysUtils;

{ TOrderedBlockAccountList }

Type
  TOrderedBlockAccount = Record
    block : Cardinal;
    memBlock : TMemBlockAccount;
  end;
  POrderedBlockAccount = ^TOrderedBlockAccount;

function TOrderedBlockAccountList.Find(const block_number: Cardinal; out Index: Integer): Boolean;
var L, H, I: Integer;
  C : Int64;
begin
  Result := False;
  L := 0;
  H := FList.Count - 1;
  while L <= H do
  begin
    I := (L + H) shr 1;
    C := Int64(POrderedBlockAccount(FList[I])^.block) - Int64(block_number);
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

function TOrderedBlockAccountList.SaveBlockAccount(const blockAccount: TBlockAccount; UpdateIfFound: Boolean): Integer;
Var P : POrderedBlockAccount;
begin
  If Not Find(blockAccount.blockchainInfo.block,Result) then begin
    New(P);
    P^.block:=blockAccount.blockchainInfo.block;
    FList.Insert(Result,P);
    ToTMemBlockAccount(blockAccount,P^.memBlock);
    If blockAccount.blockchainInfo.block>FMaxBlockNumber then FMaxBlockNumber:=blockAccount.blockchainInfo.block;
  end else if (UpdateIfFound) then begin
    P := FList[Result];
    ToTMemBlockAccount(blockAccount,P^.memBlock);
  end;
end;

constructor TOrderedBlockAccountList.Create;
begin
  FList := TList.Create;
  FMaxBlockNumber:=-1;
end;

destructor TOrderedBlockAccountList.Destroy;
begin
  Clear;
  FreeAndNil(FList);
  inherited Destroy;
end;

procedure TOrderedBlockAccountList.Clear;
var P : POrderedBlockAccount;
  i : Integer;
begin
  For i:=0 to FList.Count-1 do begin
    P := FList[i];
    Dispose(P);
  end;
  FList.Clear;
  FMaxBlockNumber:=-1;
end;

function TOrderedBlockAccountList.AddIfNotExists(const blockAccount: TBlockAccount): Integer;
begin
  SaveBlockAccount(blockAccount,False);
end;

function TOrderedBlockAccountList.Add(const blockAccount: TBlockAccount): Integer;
begin
  SaveBlockAccount(blockAccount,True);
end;

function TOrderedBlockAccountList.Count: Integer;
begin
  Result := FList.Count;
end;

function TOrderedBlockAccountList.Get(index: Integer): TBlockAccount;
begin
  ToTBlockAccount(POrderedBlockAccount(FList[index])^.memBlock,POrderedBlockAccount(FList[index])^.block,Result);
end;

function TOrderedBlockAccountList.MaxBlockNumber: Integer;
begin
  Result := FMaxBlockNumber;
end;

end.
