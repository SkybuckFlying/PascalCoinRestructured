unit UAccountPreviousBlockInfo;

interface

uses
  Classes, UAccountPreviousBlockInfoData;

type
  { TAccountPreviousBlockInfo }
  TAccountPreviousBlockInfo = Class
  private
    FList : TList;
    Function FindAccount(const account: Cardinal; var Index: Integer): Boolean;
    function GetData(index : Integer): TAccountPreviousBlockInfoData;
  public
    Constructor Create;
    Destructor Destroy; override;
    Procedure UpdateIfLower(account, previous_updated_block : Cardinal);
    Function Add(account, previous_updated_block : Cardinal) : Integer;
    Procedure Remove(account : Cardinal);
    Procedure Clear;
    Procedure CopyFrom(Sender : TAccountPreviousBlockInfo);
    Function IndexOfAccount(account : Cardinal) : Integer;
    Property Data[index : Integer] : TAccountPreviousBlockInfoData read GetData;
    Function GetPreviousUpdatedBlock(account : Cardinal; defaultValue : Cardinal) : Cardinal;
    Function Count : Integer;
    procedure SaveToStream(stream : TStream);
    function LoadFromStream(stream : TStream) : Boolean;
  end;


implementation

uses
  SysUtils, UConst;

{ TAccountPreviousBlockInfo }

Type PAccountPreviousBlockInfoData = ^TAccountPreviousBlockInfoData;

function TAccountPreviousBlockInfo.FindAccount(const account: Cardinal; var Index: Integer): Boolean;
var L, H, I: Integer;
  C : Int64;
  P : PAccountPreviousBlockInfoData;
begin
  Result := False;
  L := 0;
  H := FList.Count - 1;
  while L <= H do
  begin
    I := (L + H) shr 1;
    P := FList[i];
    C := Int64(P^.Account) - Int64(account);
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

function TAccountPreviousBlockInfo.GetData(index : Integer): TAccountPreviousBlockInfoData;
begin
  Result := PAccountPreviousBlockInfoData(FList[index])^;
end;

constructor TAccountPreviousBlockInfo.Create;
begin
  FList := TList.Create;
end;

destructor TAccountPreviousBlockInfo.Destroy;
begin
  Clear;
  FreeAndNil(FList);
  inherited Destroy;
end;

procedure TAccountPreviousBlockInfo.UpdateIfLower(account, previous_updated_block: Cardinal);
Var P : PAccountPreviousBlockInfoData;
  i : Integer;
begin
  if (account>=CT_AccountsPerBlock) And (previous_updated_block=0) then Exit; // Only accounts 0..4 allow update on block 0

  if Not FindAccount(account,i) then begin
    New(P);
    P^.Account:=account;
    P^.Previous_updated_block:=previous_updated_block;
    FList.Insert(i,P);
  end else begin
    P := FList[i];
    If (P^.Previous_updated_block>previous_updated_block) then begin
      P^.Previous_updated_block:=previous_updated_block;
    end;
  end
end;

function TAccountPreviousBlockInfo.Add(account, previous_updated_block: Cardinal): Integer;
Var P : PAccountPreviousBlockInfoData;
begin
  if Not FindAccount(account,Result) then begin
    New(P);
    P^.Account:=account;
    P^.Previous_updated_block:=previous_updated_block;
    FList.Insert(Result,P);
  end else begin
    P := FList[Result];
    P^.Previous_updated_block:=previous_updated_block;
  end
end;

procedure TAccountPreviousBlockInfo.Remove(account: Cardinal);
Var i : Integer;
  P : PAccountPreviousBlockInfoData;
begin
  If FindAccount(account,i) then begin
    P := FList[i];
    FList.Delete(i);
    Dispose(P);
  end;
end;

procedure TAccountPreviousBlockInfo.Clear;
var P : PAccountPreviousBlockInfoData;
  i : Integer;
begin
  For i:=0 to FList.Count-1 do begin
    P := FList[i];
    Dispose(P);
  end;
  FList.Clear;
end;

procedure TAccountPreviousBlockInfo.CopyFrom(Sender: TAccountPreviousBlockInfo);
Var P : PAccountPreviousBlockInfoData;
  i : Integer;
begin
  if (Sender = Self) then Raise Exception.Create('ERROR DEV 20180312-4 Myself');
  Clear;
  For i:=0 to Sender.Count-1 do begin
    New(P);
    P^ := Sender.GetData(i);
    FList.Add(P);
  end;
end;

function TAccountPreviousBlockInfo.IndexOfAccount(account: Cardinal): Integer;
begin
  If Not FindAccount(account,Result) then Result := -1;
end;

function TAccountPreviousBlockInfo.GetPreviousUpdatedBlock(account: Cardinal; defaultValue : Cardinal): Cardinal;
var i : Integer;
begin
  i := IndexOfAccount(account);
  If i>=0 then Result := GetData(i).Previous_updated_block
  else Result := defaultValue;
end;

function TAccountPreviousBlockInfo.Count: Integer;
begin
  Result := FList.Count;
end;

procedure TAccountPreviousBlockInfo.SaveToStream(stream: TStream);
var i : Integer;
  c : Cardinal;
  apbi : TAccountPreviousBlockInfoData;
begin
  c := Count;
  stream.Write(c,SizeOf(c)); // Save 4 bytes for count
  for i:=0 to Count-1 do begin
    apbi := GetData(i);
    stream.Write(apbi.Account,SizeOf(apbi.Account)); // 4 bytes for account
    stream.Write(apbi.Previous_updated_block,SizeOf(apbi.Previous_updated_block)); // 4 bytes for block number
  end;
end;

function TAccountPreviousBlockInfo.LoadFromStream(stream: TStream): Boolean;
Var lastAcc,nposStreamStart : Int64;
  c : Cardinal;
  i : Integer;
  apbi : TAccountPreviousBlockInfoData;
begin
  Result := False;
  clear;
  nposStreamStart:=stream.Position;
  Try
    lastAcc := -1;
    if (stream.Read(c,SizeOf(c))<SizeOf(c)) then Exit;
    for i:=1 to c do begin
      if stream.Read(apbi.Account,SizeOf(apbi.Account)) < SizeOf(apbi.Account) then Exit; // 4 bytes for account
      if stream.Read(apbi.Previous_updated_block,SizeOf(apbi.Previous_updated_block)) < SizeOf(apbi.Previous_updated_block) then Exit; // 4 bytes for block number
      if (lastAcc >= apbi.Account) then Exit;
      Add(apbi.Account,apbi.Previous_updated_block);
      lastAcc := apbi.Account;
    end;
    Result := True;
  finally
    if Not Result then stream.Position:=nposStreamStart;
  end;
end;

end.
