unit UWIZTransferAccount;

{$mode delphi}

{ Copyright (c) 2018 by Ugochukwu Mmaduekwe

  Distributed under the MIT software license, see the accompanying file LICENSE
  or visit http://www.opensource.org/licenses/mit-license.php.

}

interface

uses
  Classes, SysUtils, Forms, Dialogs, UCrypto, UCommon, UWizard, UAccounts, LCLType, UWIZModels;

type

  { TWIZTransferAccountWizard }

  TWIZTransferAccountWizard = class(TWizard<TWIZOperationsModel>)
  private
    function UpdatePayload(const SenderAccount: TAccount; var errors: string): boolean;
    function UpdateOperationOptions(var errors: string): boolean;
    function UpdateOpChangeKey(const TargetAccount: TAccount; var SignerAccount: TAccount; var NewPublicKey: TAccountKey; var errors: ansistring): boolean;
    procedure TransferAccountOwnership();
  public
    constructor Create(AOwner: TComponent); override;
    function DetermineHasNext: boolean; override;
    function DetermineHasPrevious: boolean; override;
    function FinishRequested(out message: ansistring): boolean; override;
    function CancelRequested(out message: ansistring): boolean; override;
  end;

implementation

uses
  UBlockChain,
  UOpTransaction,
  UNode,
  UConst,
  UWallet,
  UECIES,
  UAES,
  UWIZTransferAccount_Start,
  UWIZTransferAccount_Confirmation;

{ TWIZTransferAccountWizard }

function TWIZTransferAccountWizard.UpdatePayload(const SenderAccount: TAccount; var errors: string): boolean;
var
  valid: boolean;
  payload_encrypted, payload_u: string;
  account: TAccount;
begin
  valid := False;
  payload_encrypted := '';
  Model.Payload.EncodedBytes := '';
  errors := 'Unknown error';
  payload_u := Model.Payload.Content;

  try
    if (payload_u = '') then
    begin
      valid := True;
      Exit;
    end;
    case Model.Payload.Mode of

      akaEncryptWithSender:
      begin
        // Use sender
        errors := 'Error encrypting';
        account := SenderAccount;
        payload_encrypted := ECIESEncrypt(account.accountInfo.accountKey, payload_u);
        valid := payload_encrypted <> '';
      end;

      akaEncryptWithReceiver:
      begin
        errors := 'Public key: ' + 'Error encrypting';

        if Model.TransferAccount.AccountKey.EC_OpenSSL_NID <>
          CT_Account_NUL.accountInfo.accountKey.EC_OpenSSL_NID then
        begin
          payload_encrypted := ECIESEncrypt(Model.TransferAccount.AccountKey, payload_u);
          valid := payload_encrypted <> '';
        end
        else
        begin
          valid := False;
          errors := 'Selected private key is not valid to encode';
          exit;
        end;
      end;

      akaEncryptWithPassword:
      begin
        payload_encrypted := TAESComp.EVP_Encrypt_AES256(
          payload_u, Model.Payload.Password);
        valid := payload_encrypted <> '';
      end;

      akaNotEncrypt:
      begin
        payload_encrypted := payload_u;
        valid := True;
      end

      else
      begin
        raise Exception.Create('Invalid Encryption Selection');
      end;
    end;

  finally
    if valid then
    begin
      if length(payload_encrypted) > CT_MaxPayloadSize then
      begin
        valid := False;
        errors := 'Payload size is bigger than ' + IntToStr(CT_MaxPayloadSize) +
          ' (' + IntToStr(length(payload_encrypted)) + ')';
      end;

    end;
    Model.Payload.EncodedBytes := payload_encrypted;
    Result := valid;
  end;

end;

function TWIZTransferAccountWizard.UpdateOperationOptions(var errors: string): boolean;
var
  iAcc, iWallet: integer;
  sender_account, signer_account: TAccount;
  publicKey: TAccountKey;
  wk: TWalletKey;
  e: string;
  amount: int64;
begin
  Result := False;
  errors := '';
  if not Assigned(TWallet.Keys) then
  begin
    errors := 'No wallet keys';
    Exit;
  end;

  if Length(Model.TransferAccount.SelectedAccounts) = 0 then
  begin
    errors := 'No sender account';
    Exit;
  end
  else
  begin

    for iAcc := Low(Model.TransferAccount.SelectedAccounts) to High(Model.TransferAccount.SelectedAccounts) do
    begin
      sender_account := Model.TransferAccount.SelectedAccounts[iAcc];
      iWallet := TWallet.Keys.IndexOfAccountKey(sender_account.accountInfo.accountKey);
      if (iWallet < 0) then
      begin
        errors := 'Private key of account ' +
          TAccountComp.AccountNumberToAccountTxtNumber(sender_account.account) +
          ' not found in wallet';
        Exit;
      end;
      wk := TWallet.Keys.Key[iWallet];
      if not assigned(wk.PrivateKey) then
      begin
        if wk.CryptedKey <> '' then
        begin
          // TODO: handle unlocking of encrypted wallet here
          errors := 'Wallet is password protected. Need password';
        end
        else
        begin
          errors := 'Only public key of account ' +
            TAccountComp.AccountNumberToAccountTxtNumber(sender_account.account) +
            ' found in wallet. You cannot operate with this account';
        end;
        Exit;
      end;
    end;
  end;

  Result := UpdateOpChangeKey(Model.TransferAccount.SelectedAccounts[0], signer_account,
    publicKey, errors);
  UpdatePayload(sender_account, e);
end;

function TWIZTransferAccountWizard.UpdateOpChangeKey(const TargetAccount: TAccount;
  var SignerAccount: TAccount; var NewPublicKey: TAccountKey;
  var errors: ansistring): boolean;
begin
  Result := False;
  errors := '';
  try
    if not TAccountComp.AccountKeyFromImport(Model.TransferAccount.NewPublicKey,
      NewPublicKey, errors) then
    begin
      Exit;
    end;

    if TNode.Node.Bank.SafeBox.CurrentProtocol >= 1 then
    begin
      // Signer:
      SignerAccount := Model.Signer.SignerAccount;
      if (TAccountComp.IsAccountLocked(SignerAccount.accountInfo,
        TNode.Node.Bank.BlocksCount)) then
      begin
        errors := 'Signer account ' + TAccountComp.AccountNumberToAccountTxtNumber(
          SignerAccount.account) + ' is locked until block ' + IntToStr(
          SignerAccount.accountInfo.locked_until_block);
        exit;
      end;
      if (not TAccountComp.EqualAccountKeys(
        SignerAccount.accountInfo.accountKey, TargetAccount.accountInfo.accountKey)) then
      begin
        errors := 'Signer account ' + TAccountComp.AccountNumberToAccountTxtNumber(
          SignerAccount.account) + ' is not owner of account ' +
          TAccountComp.AccountNumberToAccountTxtNumber(TargetAccount.account);
        exit;
      end;
    end
    else
    begin
      SignerAccount := TargetAccount;
    end;

    if (TAccountComp.EqualAccountKeys(TargetAccount.accountInfo.accountKey,
      NewPublicKey)) then
    begin
      errors := 'New public key is the same public key';
      exit;
    end;

  finally
    Result := errors = '';
  end;
end;

procedure TWIZTransferAccountWizard.TransferAccountOwnership();
var
  _V2, dooperation: boolean;
  iAcc, i: integer;
  _totalamount, _totalfee, _totalSignerFee, _amount, _fee: int64;
  _signer_n_ops: cardinal;
  operationstxt, operation_to_string, errors, auxs: string;
  wk: TWalletKey;
  ops: TOperationsHashTree;
  op: TPCOperation;
  account, signerAccount: TAccount;
  _newOwnerPublicKey: TECDSA_Public;
label
  loop_start;
begin
  if not Assigned(TWallet.Keys) then
    raise Exception.Create('No wallet keys');
  if not UpdateOperationOptions(errors) then
    raise Exception.Create(errors);
  ops := TOperationsHashTree.Create;

  try
    _V2 := TNode.Node.Bank.SafeBox.CurrentProtocol >= CT_PROTOCOL_2;
    _totalamount := 0;
    _totalfee := 0;
    _totalSignerFee := 0;
    _signer_n_ops := 0;
    operationstxt := '';
    operation_to_string := '';
    for iAcc := Low(Model.TransferAccount.SelectedAccounts) to High(Model.TransferAccount.SelectedAccounts) do
    begin
      loop_start:
        op := nil;
      account := Model.TransferAccount.SelectedAccounts[iAcc];
      if not UpdatePayload(account, errors) then
      begin
        raise Exception.Create('Error encoding payload of sender account ' +
          TAccountComp.AccountNumberToAccountTxtNumber(account.account) + ': ' + errors);
      end;
      i := TWallet.Keys.IndexOfAccountKey(account.accountInfo.accountKey);
      if i < 0 then
      begin
        raise Exception.Create('Sender account private key not found in Wallet');
      end;

      wk := TWallet.Keys.Key[i];
      dooperation := True;
      // Default fee
      if account.balance > uint64(Model.Fee.DefaultFee) then
        _fee := Model.Fee.DefaultFee
      else
        _fee := account.balance;

      if not UpdateOpChangeKey(account, signerAccount, _newOwnerPublicKey, errors) then
      begin
        raise Exception.Create(errors);
      end;
      if _V2 then
      begin
        // must ensure is Signer account last if included in sender accounts (not necessarily ordered enumeration)
        if (iAcc < Length(Model.TransferAccount.SelectedAccounts) - 1) and
          (account.account = signerAccount.account) then
        begin
          TArrayTool<TAccount>.Swap(Model.TransferAccount.SelectedAccounts, iAcc,
            Length(Model.TransferAccount.SelectedAccounts) - 1); // ensure signer account processed last
          // TArrayTool_internal<Cardinal>.Swap(_senderAccounts, iAcc, Length(_senderAccounts) - 1);
          goto loop_start; // TODO: remove ugly hack with refactoring!
        end;

        // Maintain correct signer fee distribution
        if uint64(_totalSignerFee) >= signerAccount.balance then
          _fee := 0
        else if signerAccount.balance - uint64(_totalSignerFee) >
          uint64(Model.Fee.DefaultFee) then
          _fee := Model.Fee.DefaultFee
        else
          _fee := signerAccount.balance - uint64(_totalSignerFee);
        op := TOpChangeKeySigned.Create(signerAccount.account,
          signerAccount.n_operation + _signer_n_ops + 1, account.account,
          wk.PrivateKey, _newOwnerPublicKey, _fee, Model.Payload.EncodedBytes);
        Inc(_signer_n_ops);
        Inc(_totalSignerFee, _fee);
      end
      else
      begin
        op := TOpChangeKey.Create(account.account, account.n_operation +
          1, account.account, wk.PrivateKey, _newOwnerPublicKey, _fee, Model.Payload.EncodedBytes);
      end;
      Inc(_totalfee, _fee);
      operationstxt :=
        'Change private key to ' + TAccountComp.GetECInfoTxt(
        _newOwnerPublicKey.EC_OpenSSL_NID);

      if Assigned(op) and (dooperation) then
      begin
        ops.AddOperationToHashTree(op);
        if operation_to_string <> '' then
          operation_to_string := operation_to_string + #10;
        operation_to_string := operation_to_string + op.ToString;
      end;
      FreeAndNil(op);
    end;

    if (ops.OperationsCount = 0) then
      raise Exception.Create('No valid operation to execute');

    if (Length(Model.TransferAccount.SelectedAccounts) > 1) then
    begin
      auxs := '';
      if Application.MessageBox(
        PChar('Execute ' + IntToStr(Length(Model.TransferAccount.SelectedAccounts)) +
        ' operations?' + #10 + 'Operation: ' + operationstxt + #10 +
        auxs + 'Total fee: ' + TAccountComp.FormatMoney(_totalfee) +
        #10 + #10 + 'Note: This operation will be transmitted to the network!'),
        PChar(Application.Title), MB_YESNO + MB_ICONINFORMATION + MB_DEFBUTTON2) <>
        idYes then
      begin
        Exit;
      end;
    end
    else
    begin
      if Application.MessageBox(PChar('Execute this operation:' + #10 +
        #10 + operation_to_string + #10 + #10 +
        'Note: This operation will be transmitted to the network!'),
        PChar(Application.Title), MB_YESNO + MB_ICONINFORMATION + MB_DEFBUTTON2) <> idYes then
      begin
        Exit;
      end;
    end;
    i := TNode.Node.AddOperations(nil, ops, nil, errors);
    if (i = ops.OperationsCount) then
    begin
      operationstxt := 'Successfully executed ' + IntToStr(i) +
        ' operations!' + #10 + #10 + operation_to_string;
      if i > 1 then
      begin

        ShowMessage(operationstxt);
      end
      else
      begin
        Application.MessageBox(
          PChar('Successfully executed ' + IntToStr(i) + ' operations!' +
          #10 + #10 + operation_to_string),
          PChar(Application.Title), MB_OK + MB_ICONINFORMATION);
      end;

    end
    else if (i > 0) then
    begin
      operationstxt := 'One or more of your operations has not been executed:' +
        #10 + 'Errors:' + #10 + errors + #10 + #10 +
        'Total successfully executed operations: ' + IntToStr(i);

      ShowMessage(operationstxt);
    end
    else
    begin
      raise Exception.Create(errors);
    end;


  finally
    ops.Free;
  end;

end;

constructor TWIZTransferAccountWizard.Create(AOwner: TComponent);
begin
  inherited Create(AOwner, [TWIZTransferAccount_Start,
    TWIZTransferAccount_Confirmation]);
  TitleText := 'Transfer Account';
  FinishText := 'Transfer Account';
end;

function TWIZTransferAccountWizard.DetermineHasNext: boolean;
begin
  Result := not (CurrentScreen is TWIZTransferAccount_Confirmation);
end;

function TWIZTransferAccountWizard.DetermineHasPrevious: boolean;
begin
  Result := inherited DetermineHasPrevious;
end;

function TWIZTransferAccountWizard.FinishRequested(out message: ansistring): boolean;
begin
  // Execute the Transfer Account Action here
  try
    Result := True;
    TransferAccountOwnership();
  except
    On E: Exception do
    begin
      Result := False;
      message := E.ToString;
    end;
  end;
end;

function TWIZTransferAccountWizard.CancelRequested(out message: ansistring): boolean;
begin
  Result := True;
end;

end.
