unit UOrderedAccountKeysList;

interface

uses
  UPCSafeBox, UThread, Classes, UAccountKey, UOrderedCardinalList, UAccountKeyArray;

type
  // This is a class to quickly find accountkeys and their respective account number/s

  { TOrderedAccountKeysList }
  TOrderedAccountKeysList = Class
  Private
    FAutoAddAll : Boolean;
    FAccountList : TPCSafeBox;
    FOrderedAccountKeysList : TPCThreadList; // An ordered list of pointers to quickly find account keys in account list
    FTotalChanges : Integer;
    Function Find(lockedList : TList; Const AccountKey: TAccountKey; var Index: Integer): Boolean;
    function GetAccountKeyChanges(index : Integer): Integer;
    function GetAccountKeyList(index: Integer): TOrderedCardinalList;
    function GetAccountKey(index: Integer): TAccountKey;
  protected
  public
    Constructor Create(AccountList : TPCSafeBox; AutoAddAll : Boolean);
    Destructor Destroy; override;

    // Skybuck: added this for now;
    procedure NillifyAccountList;

    // Skybuck: moved to here to make it accessable to TPCSafeBox
    Procedure ClearAccounts(RemoveAccountList : Boolean);

    Procedure AddAccountKey(Const AccountKey : TAccountKey);
    Procedure AddAccountKeys(Const AccountKeys : array of TAccountKey);
    Procedure RemoveAccountKey(Const AccountKey : TAccountKey);
    Procedure AddAccounts(Const AccountKey : TAccountKey; const accounts : Array of Cardinal);
    Procedure RemoveAccounts(Const AccountKey : TAccountKey; const accounts : Array of Cardinal);
    Function IndexOfAccountKey(Const AccountKey : TAccountKey) : Integer;
    Property AccountKeyList[index : Integer] : TOrderedCardinalList read GetAccountKeyList;
    Property AccountKey[index : Integer] : TAccountKey read GetAccountKey;
    Property AccountKeyChanges[index : Integer] : Integer read GetAccountKeyChanges;
    procedure ClearAccountKeyChanges;
    Function Count : Integer;
    Property SafeBox : TPCSafeBox read FAccountList;
    Procedure Clear;
    function ToArray : TAccountKeyArray;
    function Lock : TList;
    procedure Unlock;
    function HasAccountKeyChanged : Boolean;
  End;

implementation

uses
  URawBytes, UPtrInt, UAccountComp, ULog, SysUtils, UCrypto, UConst, UBaseType;

{ TOrderedAccountKeysList }
Type
  TOrderedAccountKeyList = Record
    rawaccountkey : TRawBytes;
    accounts_number : TOrderedCardinalList;
    changes_counter : Integer;
  end;
  POrderedAccountKeyList = ^TOrderedAccountKeyList;
Const
  CT_TOrderedAccountKeyList_NUL : TOrderedAccountKeyList = (rawaccountkey:'';accounts_number:Nil;changes_counter:0);

function SortOrdered(Item1, Item2: Pointer): Integer;
begin
   Result := PtrInt(Item1) - PtrInt(Item2);
end;

procedure TOrderedAccountKeysList.AddAccountKey(const AccountKey: TAccountKey);
Var P : POrderedAccountKeyList;
  i,j : Integer;
  lockedList : TList;
begin
  lockedList := Lock;
  Try
    if Not Find(lockedList,AccountKey,i) then begin
      New(P);
      P^ := CT_TOrderedAccountKeyList_NUL;
      P^.rawaccountkey := TAccountComp.AccountKey2RawString(AccountKey);
      P^.accounts_number := TOrderedCardinalList.Create;
      inc(P^.changes_counter);
      inc(FTotalChanges);
      lockedList.Insert(i,P);
      // Search this key in the AccountsList and add all...
      j := 0;
      if Assigned(FAccountList) then begin
        For i:=0 to FAccountList.AccountsCount-1 do begin
          If TAccountComp.EqualAccountKeys(FAccountList.Account(i).accountInfo.accountkey,AccountKey) then begin
            // Note: P^.accounts will be ascending ordered due to "for i:=0 to ..."
            P^.accounts_number.Add(i);
          end;
        end;
        TLog.NewLog(ltdebug,Classname,Format('Adding account key (%d of %d) %s',[j,FAccountList.AccountsCount,TCrypto.ToHexaString(TAccountComp.AccountKey2RawString(AccountKey))]));
      end else begin
        TLog.NewLog(ltdebug,Classname,Format('Adding account key (no Account List) %s',[TCrypto.ToHexaString(TAccountComp.AccountKey2RawString(AccountKey))]));
      end;
    end;
  finally
    Unlock;
  end;
end;

Procedure TOrderedAccountKeysList.AddAccountKeys(Const AccountKeys : array of TAccountKey);
var i : integer;
begin
  for i := Low(AccountKeys) to High(AccountKeys) do
    AddAccountKey(AccountKeys[i]);
end;

procedure TOrderedAccountKeysList.AddAccounts(const AccountKey: TAccountKey; const accounts: array of Cardinal);
Var P : POrderedAccountKeyList;
  i,i2 : Integer;
  lockedList : TList;
begin
  lockedList := Lock;
  Try
    if Find(lockedList,AccountKey,i) then begin
      P :=  POrderedAccountKeyList(lockedList[i]);
    end else if (FAutoAddAll) then begin
      New(P);
      P^ := CT_TOrderedAccountKeyList_NUL;
      P^.rawaccountkey := TAccountComp.AccountKey2RawString(AccountKey);
      P^.accounts_number := TOrderedCardinalList.Create;
      lockedList.Insert(i,P);
    end else exit;
    for i := Low(accounts) to High(accounts) do begin
      P^.accounts_number.Add(accounts[i]);
    end;
    inc(P^.changes_counter);
    inc(FTotalChanges);
  finally
    Unlock;
  end;
end;

procedure TOrderedAccountKeysList.Clear;
begin
  Lock;
  Try
    ClearAccounts(true);
    FTotalChanges := 1; // 1 = At least 1 change
  finally
    Unlock;
  end;
end;

function TOrderedAccountKeysList.ToArray : TAccountKeyArray;
var i : Integer;
begin
  Lock;
  Try
    SetLength(Result, Count);
    for i := 0 to Count - 1 do Result[i] := Self.AccountKey[i];
  finally
    Unlock;
  end;
end;

function TOrderedAccountKeysList.Lock: TList;
begin
  Result := FOrderedAccountKeysList.LockList;
end;

procedure TOrderedAccountKeysList.Unlock;
begin
  FOrderedAccountKeysList.UnlockList;
end;

function TOrderedAccountKeysList.HasAccountKeyChanged: Boolean;
begin
  Result := FTotalChanges>0;
end;

procedure TOrderedAccountKeysList.ClearAccounts(RemoveAccountList : Boolean);
Var P : POrderedAccountKeyList;
  i : Integer;
  lockedList : TList;
begin
  lockedList := Lock;
  Try
    for i := 0 to  lockedList.Count - 1 do begin
      P := lockedList[i];
      inc(P^.changes_counter);
      if RemoveAccountList then begin
        P^.accounts_number.Free;
        Dispose(P);
      end else begin
        P^.accounts_number.Clear;
      end;
    end;
    if RemoveAccountList then begin
      lockedList.Clear;
    end;
    FTotalChanges:=lockedList.Count + 1; // At least 1 change
  finally
    Unlock;
  end;
end;

function TOrderedAccountKeysList.Count: Integer;
var lockedList : TList;
begin
  lockedList := Lock;
  Try
    Result := lockedList.Count;
  finally
    Unlock;
  end;
end;

constructor TOrderedAccountKeysList.Create(AccountList : TPCSafeBox; AutoAddAll : Boolean);
Var i : Integer;
begin
  TLog.NewLog(ltdebug,Classname,'Creating an Ordered Account Keys List adding all:'+CT_TRUE_FALSE[AutoAddAll]);
  FAutoAddAll := AutoAddAll;
  FAccountList := AccountList;
  FTotalChanges:=0;
  FOrderedAccountKeysList := TPCThreadList.Create(ClassName);
  if Assigned(AccountList) then begin
    Lock;
    Try
      AccountList.ListOfOrderedAccountKeysList.Add(Self);
      if AutoAddAll then begin
        for i := 0 to AccountList.AccountsCount - 1 do begin
          AddAccountKey(AccountList.Account(i).accountInfo.accountkey);
        end;
      end;
    finally
      Unlock;
    end;
  end;
end;

destructor TOrderedAccountKeysList.Destroy;
begin
  TLog.NewLog(ltdebug,Classname,'Destroying an Ordered Account Keys List adding all:'+CT_TRUE_FALSE[FAutoAddAll]);
  if Assigned(FAccountList) then begin
    FAccountList.ListOfOrderedAccountKeysList.Remove(Self);
  end;
  ClearAccounts(true);
  FreeAndNil(FOrderedAccountKeysList);
  inherited;
end;

function TOrderedAccountKeysList.Find(lockedList : TList; const AccountKey: TAccountKey; var Index: Integer): Boolean;
var L, H, I, C: Integer;
  rak : TRawBytes;
begin
  Result := False;
  rak := TAccountComp.AccountKey2RawString(AccountKey);
  L := 0;
  H := lockedList.Count - 1;
  while L <= H do
  begin
    I := (L + H) shr 1;
    C := TBaseType.BinStrComp( POrderedAccountKeyList(lockedList[I]).rawaccountkey, rak );
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

function TOrderedAccountKeysList.GetAccountKeyChanges(index : Integer): Integer;
var lockedList : TList;
begin
  lockedList := Lock;
  Try
    Result :=  POrderedAccountKeyList(lockedList[index])^.changes_counter;
  finally
    Unlock;
  end;
end;

function TOrderedAccountKeysList.GetAccountKey(index: Integer): TAccountKey;
Var raw : TRawBytes;
  lockedList : TList;
begin
  lockedList := Lock;
  Try
    raw := POrderedAccountKeyList(lockedList[index]).rawaccountkey;
  finally
    Unlock;
  end;
  Result := TAccountComp.RawString2Accountkey(raw);
end;

function TOrderedAccountKeysList.GetAccountKeyList(index: Integer): TOrderedCardinalList;
var lockedList : TList;
begin
  lockedList := Lock;
  Try
    Result := POrderedAccountKeyList(lockedList[index]).accounts_number;
  finally
    Unlock;
  end;
end;

function TOrderedAccountKeysList.IndexOfAccountKey(const AccountKey: TAccountKey): Integer;
var lockedList : TList;
begin
  lockedList := Lock;
  Try
    If Not Find(lockedList,AccountKey,Result) then Result := -1;
  finally
    Unlock;
  end;
end;

procedure TOrderedAccountKeysList.ClearAccountKeyChanges;
var i : Integer;
  lockedList : TList;
begin
  lockedList := Lock;
  Try
    for i:=0 to lockedList.Count-1 do begin
      POrderedAccountKeyList(lockedList[i])^.changes_counter:=0;
    end;
    FTotalChanges:=0;
  finally
    Unlock;
  end;
end;

procedure TOrderedAccountKeysList.RemoveAccounts(const AccountKey: TAccountKey; const accounts: array of Cardinal);
Var P : POrderedAccountKeyList;
  i,j : Integer;
  lockedList : TList;
begin
  lockedList := Lock;
  Try
    if Not Find(lockedList,AccountKey,i) then exit; // Nothing to do
    P :=  POrderedAccountKeyList(lockedList[i]);
    inc(P^.changes_counter);
    inc(FTotalChanges);
    for j := Low(accounts) to High(accounts) do begin
      P^.accounts_number.Remove(accounts[j]);
    end;
    if (P^.accounts_number.Count=0) And (FAutoAddAll) then begin
      // Remove from list
      lockedList.Delete(i);
      // Free it
      P^.accounts_number.free;
      Dispose(P);
    end;
  finally
    Unlock;
  end;
end;

procedure TOrderedAccountKeysList.RemoveAccountKey(const AccountKey: TAccountKey);
Var P : POrderedAccountKeyList;
  i,j : Integer;
  lockedList : TList;
begin
  lockedList := Lock;
  Try
    if Not Find(lockedList,AccountKey,i) then exit; // Nothing to do
    P :=  POrderedAccountKeyList(lockedList[i]);
    inc(P^.changes_counter);
    inc(FTotalChanges);
    // Remove from list
    lockedList.Delete(i);
    // Free it
    P^.accounts_number.free;
    Dispose(P);
  finally
    Unlock;
  end;
end;

procedure TOrderedAccountKeysList.NillifyAccountList;
begin
  FAccountList := nil;
end;



end.
