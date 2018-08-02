unit UPCSafeBoxTransaction;

interface

uses
  UOrderedAccountList, UPascalCoinSafeBox, URawBytes, UOrderedRawList, UAccount, UAccountPreviousBlockInfo, UAccountInfo, UAccountKey, UOperationBlock;

type
  { TPCSafeBoxTransaction }
  TPCSafeBoxTransaction = Class
  private
    FOrderedList : TOrderedAccountList;
    FFreezedAccounts : TPCSafeBox;
    FTotalBalance: Int64;
    FTotalFee: Int64;
    FOldSafeBoxHash : TRawBytes;
    FAccountNames_Deleted : TOrderedRawList;
    FAccountNames_Added : TOrderedRawList;
    Function Origin_BlocksCount : Cardinal;
    Function Origin_SafeboxHash : TRawBytes;
    Function Origin_TotalBalance : Int64;
    Function Origin_TotalFee : Int64;
    Function Origin_FindAccountByName(const account_name : AnsiString) : Integer;
  protected
    Function GetInternalAccount(account_number : Cardinal) : PAccount;
  public
    Constructor Create(SafeBox : TPCSafeBox);
    Destructor Destroy; override;
    Function TransferAmount(previous : TAccountPreviousBlockInfo; sender,target : Cardinal; n_operation : Cardinal; amount, fee : UInt64; var errors : AnsiString) : Boolean;
    Function TransferAmounts(previous : TAccountPreviousBlockInfo; const senders, n_operations : Array of Cardinal; const sender_amounts : Array of UInt64; const receivers : Array of Cardinal; const receivers_amounts : Array of UInt64; var errors : AnsiString) : Boolean;
    Function UpdateAccountInfo(previous : TAccountPreviousBlockInfo; signer_account, signer_n_operation, target_account: Cardinal; accountInfo: TAccountInfo; newName : TRawBytes; newType : Word; fee: UInt64; var errors : AnsiString) : Boolean;
    Function BuyAccount(previous : TAccountPreviousBlockInfo; buyer,account_to_buy,seller: Cardinal; n_operation : Cardinal; amount, account_price, fee : UInt64; const new_account_key : TAccountKey; var errors : AnsiString) : Boolean;
    Function Commit(Const operationBlock : TOperationBlock; var errors : AnsiString) : Boolean;
    Function Account(account_number : Cardinal) : TAccount;
    Procedure Rollback;
    Function CheckIntegrity : Boolean;
    Property FreezedSafeBox : TPCSafeBox read FFreezedAccounts;
    Property TotalFee : Int64 read FTotalFee;
    Property TotalBalance : Int64 read FTotalBalance;
    Procedure CopyFrom(transaction : TPCSafeBoxTransaction);
    Procedure CleanTransaction;
    Function ModifiedCount : Integer;
    Function Modified(index : Integer) : TAccount;
    Function FindAccountByNameInTransaction(const findName : TRawBytes; out isAddedInThisTransaction, isDeletedInThisTransaction : Boolean) : Integer;
  End;

implementation

uses
  UConst, UAccountComp, SysUtils, UCrypto, UAccountState, UAccountUpdateStyle, ULog, UECDSA_Public;

{ TPCSafeBoxTransaction }

function TPCSafeBoxTransaction.Account(account_number: Cardinal): TAccount;
Var i :Integer;
begin
  if FOrderedList.Find(account_number,i) then Result := PAccount(FOrderedList.List[i])^
  else begin
    Result := FreezedSafeBox.Account(account_number);
  end;
end;

function TPCSafeBoxTransaction.BuyAccount(previous : TAccountPreviousBlockInfo; buyer, account_to_buy,
  seller: Cardinal; n_operation: Cardinal; amount, account_price, fee: UInt64;
  const new_account_key: TAccountKey; var errors: AnsiString): Boolean;
Var PaccBuyer, PaccAccountToBuy, PaccSeller : PAccount;
begin
  Result := false;
  errors := '';
  if not CheckIntegrity then begin
    errors := 'Invalid integrity in accounts transaction';
    exit;
  end;
  if (buyer<0) Or (buyer>=(Origin_BlocksCount*CT_AccountsPerBlock)) Or
     (account_to_buy<0) Or (account_to_buy>=(Origin_BlocksCount*CT_AccountsPerBlock)) Or
     (seller<0) Or (seller>=(Origin_BlocksCount*CT_AccountsPerBlock)) then begin
     errors := 'Invalid account number on buy';
     exit;
  end;
  if TAccountComp.IsAccountBlockedByProtocol(buyer,Origin_BlocksCount) then begin
    errors := 'Buyer account is blocked for protocol';
    Exit;
  end;
  if TAccountComp.IsAccountBlockedByProtocol(account_to_buy,Origin_BlocksCount) then begin
    errors := 'Account to buy is blocked for protocol';
    Exit;
  end;
  if TAccountComp.IsAccountBlockedByProtocol(seller,Origin_BlocksCount) then begin
    errors := 'Seller account is blocked for protocol';
    Exit;
  end;
  PaccBuyer := GetInternalAccount(buyer);
  PaccAccountToBuy := GetInternalAccount(account_to_buy);
  PaccSeller := GetInternalAccount(seller);
  if (PaccBuyer^.n_operation+1<>n_operation) then begin
    errors := 'Incorrect n_operation';
    Exit;
  end;
  if (PaccBuyer^.balance < (amount+fee)) then begin
    errors := 'Insuficient founds';
    Exit;
  end;
  if (fee>CT_MaxTransactionFee) then begin
    errors := 'Max fee';
    Exit;
  end;
  if (TAccountComp.IsAccountLocked(PaccBuyer^.accountInfo,Origin_BlocksCount)) then begin
    errors := 'Buyer account is locked until block '+Inttostr(PaccBuyer^.accountInfo.locked_until_block);
    Exit;
  end;
  If not (TAccountComp.IsAccountForSale(PaccAccountToBuy^.accountInfo)) then begin
    errors := 'Account is not for sale';
    Exit;
  end;
  if (PaccAccountToBuy^.accountInfo.new_publicKey.EC_OpenSSL_NID<>CT_TECDSA_Public_Nul.EC_OpenSSL_NID) And
     (Not TAccountComp.EqualAccountKeys(PaccAccountToBuy^.accountInfo.new_publicKey,new_account_key)) then begin
    errors := 'New public key is not equal to allowed new public key for account';
    Exit;
  end;
  // Buy an account applies when account_to_buy.amount + operation amount >= price
  // Then, account_to_buy.amount will be (account_to_buy.amount + amount - price)
  // and buyer.amount will be buyer.amount + price
  if (PaccAccountToBuy^.accountInfo.price > (PaccAccountToBuy^.balance+amount)) then begin
    errors := 'Account price '+TAccountComp.FormatMoney(PaccAccountToBuy^.accountInfo.price)+' < balance '+
      TAccountComp.FormatMoney(PaccAccountToBuy^.balance)+' + amount '+TAccountComp.FormatMoney(amount);
    Exit;
  end;

  previous.UpdateIfLower(PaccBuyer^.account,PaccBuyer^.updated_block);
  previous.UpdateIfLower(PaccAccountToBuy^.account,PaccAccountToBuy^.updated_block);
  previous.UpdateIfLower(PaccSeller^.account,PaccSeller^.updated_block);

  If PaccBuyer^.updated_block<>Origin_BlocksCount then begin
    PaccBuyer^.previous_updated_block := PaccBuyer^.updated_block;
    PaccBuyer^.updated_block := Origin_BlocksCount;
  end;

  If PaccAccountToBuy^.updated_block<>Origin_BlocksCount then begin
    PaccAccountToBuy^.previous_updated_block := PaccAccountToBuy^.updated_block;
    PaccAccountToBuy^.updated_block := Origin_BlocksCount;
  end;

  If PaccSeller^.updated_block<>Origin_BlocksCount then begin
    PaccSeller^.previous_updated_block := PaccSeller^.updated_block;
    PaccSeller^.updated_block := Origin_BlocksCount;
  end;

  // Inc buyer n_operation
  PaccBuyer^.n_operation := n_operation;
  // Set new balance values
  PaccBuyer^.balance := PaccBuyer^.balance - (amount + fee);
  PaccAccountToBuy^.balance := PaccAccountToBuy^.balance + amount - PaccAccountToBuy^.accountInfo.price;
  PaccSeller^.balance := PaccSeller^.balance + PaccAccountToBuy^.accountInfo.price;

  // After buy, account will be unlocked and set to normal state and new account public key changed
  PaccAccountToBuy^.accountInfo := CT_AccountInfo_NUL;
  PaccAccountToBuy^.accountInfo.state := as_Normal;
  PaccAccountToBuy^.accountInfo.accountKey := new_account_key;

  FTotalBalance := FTotalBalance - fee;
  FTotalFee := FTotalFee + fee;
  Result := true;
end;

function TPCSafeBoxTransaction.CheckIntegrity: Boolean;
begin
  Result := FOldSafeBoxHash = Origin_SafeboxHash;
end;

procedure TPCSafeBoxTransaction.CleanTransaction;
begin
  FOrderedList.Clear;
  FOldSafeBoxHash := Origin_SafeboxHash;
  FTotalBalance := Origin_TotalBalance;
  FTotalFee := 0;
  FAccountNames_Added.Clear;
  FAccountNames_Deleted.Clear;
end;

function TPCSafeBoxTransaction.Commit(const operationBlock: TOperationBlock;
  var errors: AnsiString): Boolean;
Var i : Integer;
  Pa : PAccount;
begin
  Result := false;
  errors := '';
  FFreezedAccounts.StartThreadSafe;
  try
    if not CheckIntegrity then begin
      errors := 'Invalid integrity in accounts transaction on commit';
      exit;
    end;
    for i := 0 to FOrderedList.List.Count - 1 do begin
      Pa := PAccount(FOrderedList.List[i]);
      FFreezedAccounts.UpdateAccount(Pa^.account,
            Pa^.accountInfo,
            Pa^.name,
            Pa^.account_type,
            Pa^.balance,
            Pa^.n_operation,
            aus_transaction_commit,
            0,0);
    end;
    //
    if (Origin_TotalBalance<>FTotalBalance) then begin
      TLog.NewLog(lterror,ClassName,Format('Invalid integrity balance! StrongBox:%d Transaction:%d',[Origin_TotalBalance,FTotalBalance]));
    end;
    if (Origin_TotalFee<>FTotalFee) then begin
      TLog.NewLog(lterror,ClassName,Format('Invalid integrity fee! StrongBox:%d Transaction:%d',[Origin_TotalFee,FTotalFee]));
    end;
    FFreezedAccounts.AddNew(operationBlock);
    CleanTransaction;
    //
    if (FFreezedAccounts.CurrentProtocol<CT_PROTOCOL_2) And (operationBlock.protocol_version=CT_PROTOCOL_2) then begin
      // First block with new protocol!
      if FFreezedAccounts.CanUpgradeToProtocol(CT_PROTOCOL_2) then begin
        TLog.NewLog(ltInfo,ClassName,'Protocol upgrade to v2');
        If not FFreezedAccounts.DoUpgradeToProtocol2 then begin
          raise Exception.Create('Cannot upgrade to protocol v2 !');
        end;
      end;
    end;
    if (FFreezedAccounts.CurrentProtocol<CT_PROTOCOL_3) And (operationBlock.protocol_version=CT_PROTOCOL_3) then begin
      // First block with V3 protocol
      if FFreezedAccounts.CanUpgradeToProtocol(CT_PROTOCOL_3) then begin
        TLog.NewLog(ltInfo,ClassName,'Protocol upgrade to v3');
        If not FFreezedAccounts.DoUpgradeToProtocol3 then begin
          raise Exception.Create('Cannot upgrade to protocol v3 !');
        end;
      end;
    end;
    Result := true;
  finally
    FFreezedAccounts.EndThreadSave;
  end;
end;

procedure TPCSafeBoxTransaction.CopyFrom(transaction : TPCSafeBoxTransaction);
Var i : Integer;
  P : PAccount;
begin
  if transaction=Self then exit;
  if transaction.FFreezedAccounts<>FFreezedAccounts then raise Exception.Create('Invalid Freezed accounts to copy');
  CleanTransaction;
  for i := 0 to transaction.FOrderedList.List.Count - 1 do begin
    P := PAccount(transaction.FOrderedList.List[i]);
    FOrderedList.Add(P^);
  end;
  FOldSafeBoxHash := transaction.FOldSafeBoxHash;
  FTotalBalance := transaction.FTotalBalance;
  FTotalFee := transaction.FTotalFee;
end;

constructor TPCSafeBoxTransaction.Create(SafeBox : TPCSafeBox);
begin
  FOrderedList := TOrderedAccountList.Create;
  FFreezedAccounts := SafeBox;
  FOldSafeBoxHash := SafeBox.SafeBoxHash;
  FTotalBalance := FFreezedAccounts.TotalBalance;
  FTotalFee := 0;
  FAccountNames_Added := TOrderedRawList.Create;
  FAccountNames_Deleted := TOrderedRawList.Create;
end;

destructor TPCSafeBoxTransaction.Destroy;
begin
  CleanTransaction;
  FreeAndNil(FOrderedList);
  FreeAndNil(FAccountNames_Added);
  FreeAndNil(FAccountNames_Deleted);
  inherited;
end;

function TPCSafeBoxTransaction.Origin_BlocksCount: Cardinal;
begin
  Result := FFreezedAccounts.BlocksCount;
end;

function TPCSafeBoxTransaction.Origin_SafeboxHash: TRawBytes;
begin
  Result := FFreezedAccounts.SafeBoxHash;
end;

function TPCSafeBoxTransaction.Origin_TotalBalance: Int64;
begin
  Result := FFreezedAccounts.TotalBalance;
end;

function TPCSafeBoxTransaction.Origin_TotalFee: Int64;
begin
  Result := FFreezedAccounts.TotalFee;
end;

function TPCSafeBoxTransaction.Origin_FindAccountByName(const account_name: AnsiString): Integer;
begin
  Result := FFreezedAccounts.FindAccountByName(account_name);
end;

function TPCSafeBoxTransaction.GetInternalAccount(account_number: Cardinal): PAccount;
Var i :Integer;
begin
  if FOrderedList.Find(account_number,i) then Result := PAccount(FOrderedList.List[i])
  else begin
    i := FOrderedList.Add( FreezedSafeBox.Account(account_number) );
    Result := PAccount(FOrderedList.List[i]);
  end;
end;

function TPCSafeBoxTransaction.Modified(index: Integer): TAccount;
begin
  Result := FOrderedList.Get(index);
end;

function TPCSafeBoxTransaction.FindAccountByNameInTransaction(const findName: TRawBytes; out isAddedInThisTransaction, isDeletedInThisTransaction : Boolean) : Integer;
Var nameLower : AnsiString;
  iSafeBox, iAdded, iDeleted : Integer;
begin
  Result := -1;
  isAddedInThisTransaction := False;
  isDeletedInThisTransaction := False;
  nameLower := LowerCase(findName);
  If (nameLower)='' then begin
    Exit; // No name, no found
  end;
  iSafeBox := Origin_FindAccountByName(nameLower);
  iAdded := FAccountNames_Added.IndexOf(nameLower);
  iDeleted := FAccountNames_Deleted.IndexOf(nameLower);
  isAddedInThisTransaction := (iAdded >= 0);
  isDeletedInThisTransaction := (iDeleted >= 0);
  if (iSafeBox<0) then begin
    // Not found previously, check added in current trans?
    If iAdded>=0 then begin
      Result := FAccountNames_Added.GetTag(iAdded);
    end;
  end else begin
    // Was found previously, check if deleted
    if iDeleted<0 then begin
      // Not deleted! "iSafebox" value contains account number using name
      Result := iSafeBox;
    end;
  end;
end;

function TPCSafeBoxTransaction.ModifiedCount: Integer;
begin
  Result := FOrderedList.Count;
end;

procedure TPCSafeBoxTransaction.Rollback;
begin
  CleanTransaction;
end;

function TPCSafeBoxTransaction.TransferAmount(previous : TAccountPreviousBlockInfo; sender, target: Cardinal;
  n_operation: Cardinal; amount, fee: UInt64; var errors: AnsiString): Boolean;
Var
  intSender, intTarget : Integer;
  PaccSender, PaccTarget : PAccount;
begin
  Result := false;
  errors := '';
  if not CheckIntegrity then begin
    errors := 'Invalid integrity in accounts transaction';
    exit;
  end;
  if (sender<0) Or (sender>=(Origin_BlocksCount*CT_AccountsPerBlock)) Or
     (target<0) Or (target>=(Origin_BlocksCount*CT_AccountsPerBlock)) then begin
     errors := 'Invalid sender or target on transfer';
     exit;
  end;
  if TAccountComp.IsAccountBlockedByProtocol(sender,Origin_BlocksCount) then begin
    errors := 'Sender account is blocked for protocol';
    Exit;
  end;
  if TAccountComp.IsAccountBlockedByProtocol(target,Origin_BlocksCount) then begin
    errors := 'Target account is blocked for protocol';
    Exit;
  end;
  PaccSender := GetInternalAccount(sender);
  PaccTarget := GetInternalAccount(target);
  if (PaccSender^.n_operation+1<>n_operation) then begin
    errors := 'Incorrect n_operation';
    Exit;
  end;
  if (PaccSender^.balance < (amount+fee)) then begin
    errors := 'Insuficient founds';
    Exit;
  end;
  if ((PaccTarget^.balance + amount)>CT_MaxWalletAmount) then begin
    errors := 'Max account balance';
    Exit;
  end;
  if (fee>CT_MaxTransactionFee) then begin
    errors := 'Max fee';
    Exit;
  end;
  if (TAccountComp.IsAccountLocked(PaccSender^.accountInfo,Origin_BlocksCount)) then begin
    errors := 'Sender account is locked until block '+Inttostr(PaccSender^.accountInfo.locked_until_block);
    Exit;
  end;

  previous.UpdateIfLower(PaccSender^.account,PaccSender^.updated_block);
  previous.UpdateIfLower(PaccTarget^.account,PaccTarget^.updated_block);

  If PaccSender^.updated_block<>Origin_BlocksCount then begin
    PaccSender^.previous_updated_block := PaccSender^.updated_block;
    PaccSender^.updated_block := Origin_BlocksCount;
  end;

  If PaccTarget^.updated_block<>Origin_BlocksCount then begin
    PaccTarget^.previous_updated_block := PaccTarget.updated_block;
    PaccTarget^.updated_block := Origin_BlocksCount;
  end;

  PaccSender^.n_operation := n_operation;
  PaccSender^.balance := PaccSender^.balance - (amount + fee);
  PaccTarget^.balance := PaccTarget^.balance + (amount);

  FTotalBalance := FTotalBalance - fee;
  FTotalFee := FTotalFee + fee;
  Result := true;
end;

function TPCSafeBoxTransaction.TransferAmounts(previous : TAccountPreviousBlockInfo; const senders,
  n_operations: array of Cardinal; const sender_amounts: array of UInt64;
  const receivers: array of Cardinal; const receivers_amounts: array of UInt64;
  var errors: AnsiString): Boolean;
Var i,j : Integer;
  PaccSender, PaccTarget : PAccount;
  nTotalAmountSent, nTotalAmountReceived, nTotalFee : Int64;
begin
  Result := false;
  errors := '';
  nTotalAmountReceived:=0;
  nTotalAmountSent:=0;
  if not CheckIntegrity then begin
    errors := 'Invalid integrity in transfer amounts transaction';
    Exit;
  end;
  if (Length(senders)<>Length(n_operations)) Or
     (Length(senders)<>Length(sender_amounts)) Or
     (Length(senders)=0)
     then begin
    errors := 'Invalid senders/n_operations/amounts arrays length';
    Exit;
  end;
  if (Length(receivers)<>Length(receivers_amounts)) Or
     (Length(receivers)=0) then begin
    errors := 'Invalid receivers/amounts arrays length';
    Exit;
  end;
  // Check sender
  for i:=Low(senders) to High(senders) do begin
    for j:=i+1 to High(senders) do begin
      if (senders[i]=senders[j]) then begin
        errors := 'Duplicated sender';
        Exit;
      end;
    end;
    if (senders[i]<0) Or (senders[i]>=(Origin_BlocksCount*CT_AccountsPerBlock)) then begin
       errors := 'Invalid sender on transfer';
       exit;
    end;
    if TAccountComp.IsAccountBlockedByProtocol(senders[i],Origin_BlocksCount) then begin
      errors := 'Sender account is blocked for protocol';
      Exit;
    end;
    if (sender_amounts[i]<=0) then begin
      errors := 'Invalid amount for multiple sender';
      Exit;
    end;
    PaccSender := GetInternalAccount(senders[i]);
    if (PaccSender^.n_operation+1<>n_operations[i]) then begin
      errors := 'Incorrect multisender n_operation';
      Exit;
    end;
    if (PaccSender^.balance < sender_amounts[i]) then begin
      errors := 'Insuficient funds';
      Exit;
    end;
    if (TAccountComp.IsAccountLocked(PaccSender^.accountInfo,Origin_BlocksCount)) then begin
      errors := 'Multi sender account is locked until block '+Inttostr(PaccSender^.accountInfo.locked_until_block);
      Exit;
    end;
    nTotalAmountSent := nTotalAmountSent + sender_amounts[i];
  end;
  //
  for i:=Low(receivers) to High(receivers) do begin
    if (receivers[i]<0) Or (receivers[i]>=(Origin_BlocksCount*CT_AccountsPerBlock)) then begin
       errors := 'Invalid receiver on transfer';
       exit;
    end;
    if TAccountComp.IsAccountBlockedByProtocol(receivers[i],Origin_BlocksCount) then begin
      errors := 'Receiver account is blocked for protocol';
      Exit;
    end;
    if (receivers_amounts[i]<=0) then begin
      errors := 'Invalid amount for multiple receivers';
      Exit;
    end;
    nTotalAmountReceived := nTotalAmountReceived + receivers_amounts[i];
    PaccTarget := GetInternalAccount(receivers[i]);
    if ((PaccTarget^.balance + receivers_amounts[i])>CT_MaxWalletAmount) then begin
      errors := 'Max receiver balance';
      Exit;
    end;
  end;
  //
  nTotalFee := nTotalAmountSent - nTotalAmountReceived;
  If (nTotalAmountSent<nTotalAmountReceived) then begin
    errors := 'Total amount sent < total amount received';
    Exit;
  end;
  if (nTotalFee>CT_MaxTransactionFee) then begin
    errors := 'Max fee';
    Exit;
  end;
  // Ok, execute!
  for i:=Low(senders) to High(senders) do begin
    PaccSender := GetInternalAccount(senders[i]);
    previous.UpdateIfLower(PaccSender^.account,PaccSender^.updated_block);
    If PaccSender^.updated_block<>Origin_BlocksCount then begin
      PaccSender^.previous_updated_block := PaccSender^.updated_block;
      PaccSender^.updated_block := Origin_BlocksCount;
    end;
    Inc(PaccSender^.n_operation);
    PaccSender^.balance := PaccSender^.balance - (sender_amounts[i]);
  end;
  for i:=Low(receivers) to High(receivers) do begin
    PaccTarget := GetInternalAccount(receivers[i]);
    previous.UpdateIfLower(PaccTarget^.account,PaccTarget^.updated_block);
    If PaccTarget^.updated_block<>Origin_BlocksCount then begin
      PaccTarget^.previous_updated_block := PaccTarget.updated_block;
      PaccTarget^.updated_block := Origin_BlocksCount;
    end;
    PaccTarget^.balance := PaccTarget^.balance + receivers_amounts[i];
  end;
  FTotalBalance := FTotalBalance - nTotalFee;
  FTotalFee := FTotalFee + nTotalFee;
  Result := true;
end;

function TPCSafeBoxTransaction.UpdateAccountInfo(previous : TAccountPreviousBlockInfo;
  signer_account, signer_n_operation, target_account: Cardinal;
  accountInfo: TAccountInfo; newName: TRawBytes; newType: Word; fee: UInt64; var errors: AnsiString): Boolean;
Var i : Integer;
  P_signer, P_target : PAccount;
begin
  Result := false;
  errors := '';
  if not CheckIntegrity then begin
    errors := 'Invalid integrity on Update account info';
    Exit;
  end;
  if (signer_account<0) Or (signer_account>=(Origin_BlocksCount*CT_AccountsPerBlock)) Or
     (target_account<0) Or (target_account>=(Origin_BlocksCount*CT_AccountsPerBlock)) Then begin
     errors := 'Invalid account';
     exit;
  end;
  if (TAccountComp.IsAccountBlockedByProtocol(signer_account,Origin_BlocksCount)) Or
     (TAccountComp.IsAccountBlockedByProtocol(target_account,Origin_BlocksCount)) then begin
    errors := 'account is blocked for protocol';
    Exit;
  end;
  P_signer := GetInternalAccount(signer_account);
  P_target := GetInternalAccount(target_account);
  if (P_signer^.n_operation+1<>signer_n_operation) then begin
    errors := 'Incorrect n_operation';
    Exit;
  end;
  if (P_signer^.balance < fee) then begin
    errors := 'Insuficient founds';
    Exit;
  end;
  if (TAccountComp.IsAccountLocked(P_signer^.accountInfo,Origin_BlocksCount)) then begin
    errors := 'Signer account is locked until block '+Inttostr(P_signer^.accountInfo.locked_until_block);
    Exit;
  end;
  if (TAccountComp.IsAccountLocked(P_target^.accountInfo,Origin_BlocksCount)) then begin
    errors := 'Target account is locked until block '+Inttostr(P_target^.accountInfo.locked_until_block);
    Exit;
  end;
  if Not TAccountComp.EqualAccountKeys(P_signer^.accountInfo.accountKey,P_target^.accountInfo.accountKey) then begin
    errors := 'Signer and target have diff key';
    Exit;
  end;
  if (newName<>P_target^.name) then begin
    // NEW NAME CHANGE CHECK:
    if (newName<>'') then begin
      If Not TPCSafeBox.ValidAccountName(newName,errors) then begin
        errors := 'Invalid account name "'+newName+'" length:'+IntToStr(length(newName))+': '+errors;
        Exit;
      end;
      i := Origin_FindAccountByName(newName);
      if (i>=0) then begin
        // This account name is in the safebox... check if deleted:
        i := FAccountNames_Deleted.IndexOf(newName);
        if i<0 then begin
          errors := 'Account name "'+newName+'" is in current use';
          Exit;
        end;
      end;
      i := FAccountNames_Added.IndexOf(newName);
      if (i>=0) then begin
        // This account name is added in this transaction! (perhaps deleted also, but does not allow to "double add same name in same block")
        errors := 'Account name "'+newName+'" is in same transaction';
        Exit;
      end;
    end;
    // Ok, include
    if (P_target^.name<>'') then begin
      // In use in the safebox, mark as deleted
      FAccountNames_Deleted.Add(P_target^.name,target_account);
    end;
    if (newName<>'') then begin
      FAccountNames_Added.Add(newName,target_account);
    end;
  end;
  // All Ok, can do changes
  previous.UpdateIfLower(P_signer^.account,P_signer^.updated_block);
  if P_signer^.updated_block <> Origin_BlocksCount then begin
    P_signer^.previous_updated_block := P_signer^.updated_block;
    P_signer^.updated_block := Origin_BlocksCount;
  end;
  if (signer_account<>target_account) then begin
    previous.UpdateIfLower(P_target^.account,P_target^.updated_block);
    if P_target^.updated_block <> Origin_BlocksCount then begin
      P_target^.previous_updated_block := P_target^.updated_block;
      P_target^.updated_block := Origin_BlocksCount;
    end;
  end;

  P_signer^.n_operation := signer_n_operation;
  P_target^.accountInfo := accountInfo;
  P_target^.name := newName;
  P_target^.account_type := newType;
  P_signer^.balance := P_signer^.balance - fee; // Signer is who pays the fee
  FTotalBalance := FTotalBalance - fee;
  FTotalFee := FTotalFee + fee;
  Result := true;
end;

end.
