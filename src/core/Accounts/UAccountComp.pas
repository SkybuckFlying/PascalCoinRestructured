unit UAccountComp;

interface

uses
  UAccountKey, UAccountInfo, Classes, URawBytes, UCrypto, UAccount, UOperationBlock, UBlockAccount, UECPrivateKey;

type
  { TAccountComp }
  TAccountComp = Class
  private
  public
    Class Function IsValidAccountKey(const account: TAccountKey; var errors : AnsiString): Boolean;
    Class Function IsValidAccountInfo(const accountInfo: TAccountInfo; var errors : AnsiString): Boolean;
    Class Function IsAccountForSale(const accountInfo: TAccountInfo) : Boolean;
    Class Function IsAccountForSaleAcceptingTransactions(const accountInfo: TAccountInfo) : Boolean;
    Class Function GetECInfoTxt(Const EC_OpenSSL_NID: Word) : AnsiString;
    Class Procedure ValidsEC_OpenSSL_NID(list : TList);
    Class Function AccountKey2RawString(const account: TAccountKey): TRawBytes; overload;
    Class procedure AccountKey2RawString(const account: TAccountKey; var dest: TRawBytes); overload;
    Class Function RawString2Accountkey(const rawaccstr: TRawBytes): TAccountKey; overload;
    Class procedure RawString2Accountkey(const rawaccstr: TRawBytes; var dest: TAccountKey); overload;
    Class Function PrivateToAccountkey(key: TECPrivateKey): TAccountKey;
    Class Function IsAccountBlockedByProtocol(account_number, blocks_count : Cardinal) : Boolean;
    Class Function EqualAccountInfos(const accountInfo1,accountInfo2 : TAccountInfo) : Boolean;
    Class Function EqualAccountKeys(const account1,account2 : TAccountKey) : Boolean;
    Class Function EqualAccounts(const account1,account2 : TAccount) : Boolean;
    Class Function EqualOperationBlocks(const opBlock1,opBlock2 : TOperationBlock) : Boolean;
    Class Function EqualBlockAccounts(const blockAccount1,blockAccount2 : TBlockAccount) : Boolean;
    Class Function AccountNumberToAccountTxtNumber(account_number : Cardinal) : AnsiString;
    Class function AccountTxtNumberToAccountNumber(Const account_txt_number : AnsiString; var account_number : Cardinal) : Boolean;
    Class function FormatMoney(Money : Int64) : AnsiString;
    Class function FormatMoneyDecimal(Money : Int64) : Single;
    Class Function TxtToMoney(Const moneytxt : AnsiString; var money : Int64) : Boolean;
    Class Function AccountKeyFromImport(Const HumanReadable : AnsiString; var account : TAccountKey; var errors : AnsiString) : Boolean;
    Class Function AccountPublicKeyExport(Const account : TAccountKey) : AnsiString;
    Class Function AccountPublicKeyImport(Const HumanReadable : AnsiString; var account : TAccountKey; var errors : AnsiString) : Boolean;
    Class Function AccountBlock(Const account_number : Cardinal) : Cardinal;
    Class Function AccountInfo2RawString(const AccountInfo : TAccountInfo) : TRawBytes; overload;
    Class procedure AccountInfo2RawString(const AccountInfo : TAccountInfo; var dest : TRawBytes); overload;
    Class procedure SaveAccountToAStream(Stream: TStream; const Account : TAccount);
    Class Function RawString2AccountInfo(const rawaccstr: TRawBytes): TAccountInfo; overload;
    Class procedure RawString2AccountInfo(const rawaccstr: TRawBytes; var dest : TAccountInfo); overload;
    Class Function IsAccountLocked(const AccountInfo : TAccountInfo; blocks_count : Cardinal) : Boolean;
    Class procedure SaveTOperationBlockToStream(const stream : TStream; const operationBlock:TOperationBlock);
    Class Function LoadTOperationBlockFromStream(const stream : TStream; var operationBlock:TOperationBlock) : Boolean;
    Class Function AccountToTxt(const Account : TAccount) : AnsiString;
  End;

implementation

uses
  UConst, UAccountState, UStreamOp, SysUtils, UBaseType, Math, UOpenSSL, UBigNum;

{ TAccountComp }
Const CT_Base58 : AnsiString = '123456789ABCDEFGHJKLMNPQRSTUVWXYZabcdefghijkmnopqrstuvwxyz';

class function TAccountComp.AccountBlock(const account_number: Cardinal): Cardinal;
begin
  Result := account_number DIV CT_AccountsPerBlock;
end;

class function TAccountComp.AccountInfo2RawString(const AccountInfo: TAccountInfo): TRawBytes;
begin
  AccountInfo2RawString(AccountInfo,Result);
end;

class procedure TAccountComp.AccountInfo2RawString(const AccountInfo: TAccountInfo; var dest: TRawBytes);
Var ms : TMemoryStream;
  w : Word;
begin
  case AccountInfo.state of
    as_Normal: AccountKey2RawString(AccountInfo.accountKey,dest);
    as_ForSale: begin
      ms := TMemoryStream.Create;
      Try
        w := CT_AccountInfo_ForSale;
        ms.Write(w,SizeOf(w));
        //
        TStreamOp.WriteAccountKey(ms,AccountInfo.accountKey);
        ms.Write(AccountInfo.locked_until_block,SizeOf(AccountInfo.locked_until_block));
        ms.Write(AccountInfo.price,SizeOf(AccountInfo.price));
        ms.Write(AccountInfo.account_to_pay,SizeOf(AccountInfo.account_to_pay));
        TStreamOp.WriteAccountKey(ms,AccountInfo.new_publicKey);
        SetLength(dest,ms.Size);
        ms.Position := 0;
        ms.Read(dest[1],ms.Size);
      Finally
        ms.Free;
      end;
    end;
  else
    raise Exception.Create('DEVELOP ERROR 20170214-1');
  end;
end;

class procedure TAccountComp.SaveAccountToAStream(Stream: TStream; const Account: TAccount);
begin
  Stream.Write(Account.account,Sizeof(Account.account));
  TStreamOp.WriteAnsiString(Stream,AccountInfo2RawString(Account.accountInfo));
  Stream.Write(Account.balance,Sizeof(Account.balance));
  Stream.Write(Account.updated_block,Sizeof(Account.updated_block));
  Stream.Write(Account.n_operation,Sizeof(Account.n_operation));
  TStreamOp.WriteAnsiString(Stream,Account.name);
  Stream.Write(Account.account_type,SizeOf(Account.account_type));
end;

class function TAccountComp.AccountKey2RawString(const account: TAccountKey): TRawBytes;
begin
  AccountKey2RawString(account,Result);
end;

class procedure TAccountComp.AccountKey2RawString(const account: TAccountKey; var dest: TRawBytes);
Var s : TMemoryStream;
begin
  s := TMemoryStream.Create;
  try
    TStreamOp.WriteAccountKey(s,account);
    SetLength(dest,s.Size);
    s.Position := 0;
    s.Read(dest[1],s.Size);
  finally
    s.Free;
  end;
end;

class function TAccountComp.AccountKeyFromImport(const HumanReadable: AnsiString; var account: TAccountKey; var errors : AnsiString): Boolean;
Var raw : TRawBytes;
  BN, BNAux, BNBase : TBigNum;
  i,j : Integer;
  s1,s2 : AnsiString;
  i64 : Int64;
  b : Byte;
begin
  result := false;
  errors := 'Invalid length';
  account := CT_TECDSA_Public_Nul;
  if length(HumanReadable)<20 then exit;
  BN := TBigNum.Create(0);
  BNAux := TBigNum.Create;
  BNBase := TBigNum.Create(1);
  try
    for i := length(HumanReadable) downto 1 do begin
      if (HumanReadable[i]<>' ') then begin
        j := pos(HumanReadable[i],CT_Base58);
        if j=0 then begin
          errors := 'Invalid char "'+HumanReadable[i]+'" at pos '+inttostr(i)+'/'+inttostr(length(HumanReadable));
          exit;
        end;
        BNAux.Value := j-1;
        BNAux.Multiply(BNBase);
        BN.Add(BNAux);
        BNBase.Multiply(length(CT_Base58));
      end;
    end;
    // Last 8 hexa chars are the checksum of others
    s1 := Copy(BN.HexaValue,3,length(BN.HexaValue));
    s2 := copy(s1,length(s1)-7,8);
    s1 := copy(s1,1,length(s1)-8);
    raw := TCrypto.HexaToRaw(s1);
    s1 := TCrypto.ToHexaString( TCrypto.DoSha256(raw) );
    if copy(s1,1,8)<>s2 then begin
      // Invalid checksum
      errors := 'Invalid checksum';
      exit;
    end;
    try
      account := TAccountComp.RawString2Accountkey(raw);
      Result := true;
      errors := '';
    except
      // Nothing to do... invalid
      errors := 'Error on conversion from Raw to Account key';
    end;
  Finally
    BN.Free;
    BNBase.Free;
    BNAux.Free;
  end;
end;

class function TAccountComp.AccountNumberToAccountTxtNumber(account_number: Cardinal): AnsiString;
Var an : int64;
begin
  an := account_number; // Converting to int64 to prevent overflow when *101
  an := ((an * 101) MOD 89)+10;
  Result := IntToStr(account_number)+'-'+Inttostr(an);
end;

class function TAccountComp.AccountPublicKeyExport(const account: TAccountKey): AnsiString;
Var raw : TRawBytes;
  BN, BNMod, BNDiv : TBigNum;
  i : Integer;
begin
  Result := '';
  raw := AccountKey2RawString(account);
  BN := TBigNum.Create;
  BNMod := TBigNum.Create;
  BNDiv := TBigNum.Create(Length(CT_Base58));
  try
    BN.HexaValue := '01'+TCrypto.ToHexaString( raw )+TCrypto.ToHexaString(Copy(TCrypto.DoSha256(raw),1,4));
    while (Not BN.IsZero) do begin
      BN.Divide(BNDiv,BNMod);
      If (BNMod.Value>=0) And (BNMod.Value<length(CT_Base58)) then Result := CT_Base58[Byte(BNMod.Value)+1] + Result
      else raise Exception.Create('Error converting to Base 58');
    end;
  finally
    BN.Free;
    BNMod.Free;
    BNDiv.Free;
  end;
end;

class function TAccountComp.AccountPublicKeyImport(
  const HumanReadable: AnsiString; var account: TAccountKey;
  var errors: AnsiString): Boolean;
Var raw : TRawBytes;
  BN, BNAux, BNBase : TBigNum;
  i,j : Integer;
  s1,s2 : AnsiString;
  i64 : Int64;
  b : Byte;
begin
  result := false;
  errors := 'Invalid length';
  account := CT_TECDSA_Public_Nul;
  if length(HumanReadable)<20 then exit;
  BN := TBigNum.Create(0);
  BNAux := TBigNum.Create;
  BNBase := TBigNum.Create(1);
  try
    for i := length(HumanReadable) downto 1 do begin
      j := pos(HumanReadable[i],CT_Base58);
      if j=0 then begin
        errors := 'Invalid char "'+HumanReadable[i]+'" at pos '+inttostr(i)+'/'+inttostr(length(HumanReadable));
        exit;
      end;
      BNAux.Value := j-1;
      BNAux.Multiply(BNBase);
      BN.Add(BNAux);
      BNBase.Multiply(length(CT_Base58));
    end;
    // Last 8 hexa chars are the checksum of others
    s1 := Copy(BN.HexaValue,3,length(BN.HexaValue));
    s2 := copy(s1,length(s1)-7,8);
    s1 := copy(s1,1,length(s1)-8);
    raw := TCrypto.HexaToRaw(s1);
    s1 := TCrypto.ToHexaString( TCrypto.DoSha256(raw) );
    if copy(s1,1,8)<>s2 then begin
      // Invalid checksum
      errors := 'Invalid checksum';
      exit;
    end;
    try
      account := TAccountComp.RawString2Accountkey(raw);
      Result := true;
      errors := '';
    except
      // Nothing to do... invalid
      errors := 'Error on conversion from Raw to Account key';
    end;
  Finally
    BN.Free;
    BNBase.Free;
    BNAux.Free;
  end;
end;

class function TAccountComp.AccountTxtNumberToAccountNumber(const account_txt_number: AnsiString; var account_number: Cardinal): Boolean;
Var i : Integer;
  char1 : AnsiChar;
  char2 : AnsiChar;
  an,rn,anaux : Int64;
begin
  Result := false;
  if length(trim(account_txt_number))=0 then exit;
  an := 0;
  i := 1;
  while (i<=length(account_txt_number)) do begin
    if account_txt_number[i] in ['0'..'9'] then begin
      an := (an * 10) + ord( account_txt_number[i] ) - ord('0');
    end else begin
      break;
    end;
    inc(i);
  end;
  account_number := an;
  if (i>length(account_txt_number)) then begin
    result := true;
    exit;
  end;
  if (account_txt_number[i] in ['-','.',' ']) then inc(i);
  if length(account_txt_number)-1<>i then exit;
  rn := StrToIntDef(copy(account_txt_number,i,length(account_txt_number)),0);
  anaux := ((an * 101) MOD 89)+10;
  Result := rn = anaux;
end;

class function TAccountComp.EqualAccountInfos(const accountInfo1,accountInfo2 : TAccountInfo) : Boolean;
begin
  Result := (accountInfo1.state = accountInfo2.state) And (EqualAccountKeys(accountInfo1.accountKey,accountInfo2.accountKey))
    And (accountInfo1.locked_until_block = accountInfo2.locked_until_block) And (accountInfo1.price = accountInfo2.price)
    And (accountInfo1.account_to_pay = accountInfo2.account_to_pay) and (EqualAccountKeys(accountInfo1.new_publicKey,accountInfo2.new_publicKey));
end;

class function TAccountComp.EqualAccountKeys(const account1, account2: TAccountKey): Boolean;
begin
  Result := (account1.EC_OpenSSL_NID=account2.EC_OpenSSL_NID) And
    (account1.x=account2.x) And (account1.y=account2.y);
end;

class function TAccountComp.EqualAccounts(const account1, account2: TAccount): Boolean;
begin
  Result := (account1.account = account2.account)
          And (EqualAccountInfos(account1.accountInfo,account2.accountInfo))
          And (account1.balance = account2.balance)
          And (account1.updated_block = account2.updated_block)
          And (account1.n_operation = account2.n_operation)
          And (TBaseType.BinStrComp(account1.name,account2.name)=0)
          And (account1.account_type = account2.account_type)
          And (account1.previous_updated_block = account2.previous_updated_block);
end;

class function TAccountComp.EqualOperationBlocks(const opBlock1, opBlock2: TOperationBlock): Boolean;
begin
  Result := (opBlock1.block = opBlock1.block)
          And (EqualAccountKeys(opBlock1.account_key,opBlock2.account_key))
          And (opBlock1.reward = opBlock2.reward)
          And (opBlock1.fee = opBlock2.fee)
          And (opBlock1.protocol_version = opBlock2.protocol_version)
          And (opBlock1.protocol_available = opBlock2.protocol_available)
          And (opBlock1.timestamp = opBlock2.timestamp)
          And (opBlock1.compact_target = opBlock2.compact_target)
          And (opBlock1.nonce = opBlock2.nonce)
          And (TBaseType.BinStrComp(opBlock1.block_payload,opBlock2.block_payload)=0)
          And (TBaseType.BinStrComp(opBlock1.initial_safe_box_hash,opBlock2.initial_safe_box_hash)=0)
          And (TBaseType.BinStrComp(opBlock1.operations_hash,opBlock2.operations_hash)=0)
          And (TBaseType.BinStrComp(opBlock1.proof_of_work,opBlock2.proof_of_work)=0);
end;

class function TAccountComp.EqualBlockAccounts(const blockAccount1, blockAccount2: TBlockAccount): Boolean;
Var i : Integer;
begin
  Result := (EqualOperationBlocks(blockAccount1.blockchainInfo,blockAccount2.blockchainInfo))
          And (TBaseType.BinStrComp(blockAccount1.block_hash,blockAccount2.block_hash)=0)
          And (blockAccount1.accumulatedWork = blockAccount2.accumulatedWork);
  If Result then begin
    for i:=Low(blockAccount1.accounts) to High(blockAccount1.accounts) do begin
      Result := EqualAccounts(blockAccount1.accounts[i],blockAccount2.accounts[i]);
      If Not Result then Exit;
    end;
  end;
end;


class function TAccountComp.FormatMoney(Money: Int64): AnsiString;
begin
  Result := FormatFloat('#,###0.0000',(Money/10000));
end;

class function TAccountComp.FormatMoneyDecimal(Money : Int64) : Single;
begin
  Result := RoundTo( Money / 10000.0, -4);
end;

class function TAccountComp.GetECInfoTxt(const EC_OpenSSL_NID: Word): AnsiString;
begin
  case EC_OpenSSL_NID of
    CT_NID_secp256k1 : begin
      Result := 'secp256k1';
    end;
    CT_NID_secp384r1 : begin
      Result := 'secp384r1';
    end;
    CT_NID_sect283k1 : Begin
      Result := 'secp283k1';
    End;
    CT_NID_secp521r1 : begin
      Result := 'secp521r1';
    end
  else Result := '(Unknown ID:'+inttostr(EC_OpenSSL_NID)+')';
  end;
end;

class function TAccountComp.IsAccountBlockedByProtocol(account_number, blocks_count: Cardinal): Boolean;
begin
  if blocks_count<CT_WaitNewBlocksBeforeTransaction then result := true
  else begin
    Result := ((blocks_count-CT_WaitNewBlocksBeforeTransaction) * CT_AccountsPerBlock) <= account_number;
  end;
end;

class function TAccountComp.IsAccountForSale(const accountInfo: TAccountInfo): Boolean;
begin
  Result := (AccountInfo.state=as_ForSale);
end;

class function TAccountComp.IsAccountForSaleAcceptingTransactions(const accountInfo: TAccountInfo): Boolean;
var errors : AnsiString;
begin
  Result := (AccountInfo.state=as_ForSale) And (IsValidAccountKey(AccountInfo.new_publicKey,errors));
end;

class function TAccountComp.IsAccountLocked(const AccountInfo: TAccountInfo; blocks_count: Cardinal): Boolean;
begin
  Result := (AccountInfo.state=as_ForSale) And ((AccountInfo.locked_until_block)>=blocks_count);
end;

class procedure TAccountComp.SaveTOperationBlockToStream(const stream: TStream; const operationBlock: TOperationBlock);
begin
  stream.Write(operationBlock.block, Sizeof(operationBlock.block));
  TStreamOp.WriteAccountKey(stream,operationBlock.account_key);
  stream.Write(operationBlock.reward, Sizeof(operationBlock.reward));
  stream.Write(operationBlock.fee, Sizeof(operationBlock.fee));
  stream.Write(operationBlock.protocol_version, Sizeof(operationBlock.protocol_version));
  stream.Write(operationBlock.protocol_available, Sizeof(operationBlock.protocol_available));
  stream.Write(operationBlock.timestamp, Sizeof(operationBlock.timestamp));
  stream.Write(operationBlock.compact_target, Sizeof(operationBlock.compact_target));
  stream.Write(operationBlock.nonce, Sizeof(operationBlock.nonce));
  TStreamOp.WriteAnsiString(stream, operationBlock.block_payload);
  TStreamOp.WriteAnsiString(stream, operationBlock.initial_safe_box_hash);
  TStreamOp.WriteAnsiString(stream, operationBlock.operations_hash);
  TStreamOp.WriteAnsiString(stream, operationBlock.proof_of_work);
end;

class function TAccountComp.LoadTOperationBlockFromStream(const stream: TStream; var operationBlock: TOperationBlock): Boolean;
begin
  Result := False;
  operationBlock := CT_OperationBlock_NUL;
  If stream.Read(operationBlock.block, Sizeof(operationBlock.block))<Sizeof(operationBlock.block) then Exit;
  TStreamOp.ReadAccountKey(stream,operationBlock.account_key);
  stream.Read(operationBlock.reward, Sizeof(operationBlock.reward));
  stream.Read(operationBlock.fee, Sizeof(operationBlock.fee));
  stream.Read(operationBlock.protocol_version, Sizeof(operationBlock.protocol_version));
  stream.Read(operationBlock.protocol_available, Sizeof(operationBlock.protocol_available));
  stream.Read(operationBlock.timestamp, Sizeof(operationBlock.timestamp));
  stream.Read(operationBlock.compact_target, Sizeof(operationBlock.compact_target));
  stream.Read(operationBlock.nonce, Sizeof(operationBlock.nonce));
  if TStreamOp.ReadAnsiString(stream, operationBlock.block_payload) < 0 then Exit;
  if TStreamOp.ReadAnsiString(stream, operationBlock.initial_safe_box_hash) < 0 then Exit;
  if TStreamOp.ReadAnsiString(stream, operationBlock.operations_hash) < 0 then Exit;
  if TStreamOp.ReadAnsiString(stream, operationBlock.proof_of_work) < 0 then Exit;
  Result := True;
end;

class function TAccountComp.AccountToTxt(const Account: TAccount): AnsiString;
begin
  Result := Format('%s Balance:%s N_Op:%d UpdB:%d Type:%d Name:%s PK:%s',[AccountNumberToAccountTxtNumber(Account.account),
    FormatMoney(Account.balance),Account.n_operation,Account.updated_block,Account.account_type,
      Account.name,TCrypto.ToHexaString(TAccountComp.AccountInfo2RawString(Account.accountInfo))]);
end;

class function TAccountComp.IsValidAccountInfo(const accountInfo: TAccountInfo; var errors: AnsiString): Boolean;
Var s : AnsiString;
begin
  errors := '';
  case accountInfo.state of
    as_Unknown: begin
        errors := 'Account state is unknown';
        Result := false;
      end;
    as_Normal: begin
        Result := IsValidAccountKey(accountInfo.accountKey,errors);
      end;
    as_ForSale: begin
        If Not IsValidAccountKey(accountInfo.accountKey,s) then errors := errors +' '+s;
        Result := errors='';
      end;
  else
    raise Exception.Create('DEVELOP ERROR 20170214-3');
  end;
end;

class function TAccountComp.IsValidAccountKey(const account: TAccountKey; var errors : AnsiString): Boolean;
begin
  errors := '';
  case account.EC_OpenSSL_NID of
    CT_NID_secp256k1,CT_NID_secp384r1,CT_NID_sect283k1,CT_NID_secp521r1 : begin
      Result := TECPrivateKey.IsValidPublicKey(account);
      if Not Result then begin
        errors := Format('Invalid AccountKey type:%d - Length x:%d y:%d Error:%s',[account.EC_OpenSSL_NID,length(account.x),length(account.y),  ERR_error_string(ERR_get_error(),nil)]);
      end;
    end;
  else
    errors := Format('Invalid AccountKey type:%d (Unknown type) - Length x:%d y:%d',[account.EC_OpenSSL_NID,length(account.x),length(account.y)]);
    Result := False;
  end;
  if (errors='') And (Not Result) then errors := ERR_error_string(ERR_get_error(),nil);
end;

class function TAccountComp.PrivateToAccountkey(key: TECPrivateKey): TAccountKey;
begin
  Result := key.PublicKey;
end;

class function TAccountComp.RawString2AccountInfo(const rawaccstr: TRawBytes): TAccountInfo;
begin
  RawString2AccountInfo(rawaccstr,Result);
end;

class procedure TAccountComp.RawString2AccountInfo(const rawaccstr: TRawBytes; var dest: TAccountInfo);
Var ms : TMemoryStream;
  w : Word;
begin
  if length(rawaccstr)=0 then begin
    dest := CT_AccountInfo_NUL;
    exit;
  end;
  ms := TMemoryStream.Create;
  Try
    ms.WriteBuffer(rawaccstr[1],length(rawaccstr));
    ms.Position := 0;
    If ms.Read(w,SizeOf(w))<>SizeOf(w) then exit;
    case w of
      CT_NID_secp256k1,CT_NID_secp384r1,CT_NID_sect283k1,CT_NID_secp521r1 : Begin
        dest.state := as_Normal;
        RawString2Accountkey(rawaccstr,dest.accountKey);
        dest.locked_until_block:=CT_AccountInfo_NUL.locked_until_block;
        dest.price:=CT_AccountInfo_NUL.price;
        dest.account_to_pay:=CT_AccountInfo_NUL.account_to_pay;
        dest.new_publicKey:=CT_AccountInfo_NUL.new_publicKey;
      End;
      CT_AccountInfo_ForSale : Begin
        TStreamOp.ReadAccountKey(ms,dest.accountKey);
        ms.Read(dest.locked_until_block,SizeOf(dest.locked_until_block));
        ms.Read(dest.price,SizeOf(dest.price));
        ms.Read(dest.account_to_pay,SizeOf(dest.account_to_pay));
        TStreamOp.ReadAccountKey(ms,dest.new_publicKey);
        dest.state := as_ForSale;
      End;
    else
      raise Exception.Create('DEVELOP ERROR 20170214-2');
    end;
  Finally
    ms.Free;
  end;
end;

class function TAccountComp.RawString2Accountkey(const rawaccstr: TRawBytes): TAccountKey;
begin
  RawString2Accountkey(rawaccstr,Result);
end;

class procedure TAccountComp.RawString2Accountkey(const rawaccstr: TRawBytes; var dest: TAccountKey);
Var ms : TMemoryStream;
begin
  if length(rawaccstr)=0 then begin
    dest := CT_TECDSA_Public_Nul;
    exit;
  end;
  ms := TMemoryStream.Create;
  try
    ms.WriteBuffer(rawaccstr[1],length(rawaccstr));
    ms.Position := 0;
    TStreamOp.ReadAccountKey(ms,dest);
  finally
    ms.Free;
  end;
end;

class function TAccountComp.TxtToMoney(const moneytxt: AnsiString;
  var money: Int64): Boolean;
Var s : AnsiString;
  i : Integer;
begin
  money := 0;
  if Trim(moneytxt)='' then begin
    Result := true;
    exit;
  end;
  try
    // Delphi 6 introduced "conditional compilation" and Delphi XE 6 (27) introduced FormatSettings variable.
    {$IF Defined(DCC) and Declared(CompilerVersion) and (CompilerVersion >= 27.0)}
    If pos(FormatSettings.DecimalSeparator,moneytxt)<=0 then begin
      // No decimal separator, consider ThousandSeparator as a decimal separator
      s := StringReplace(moneytxt,FormatSettings.ThousandSeparator,FormatSettings.DecimalSeparator,[rfReplaceAll]);
    end else begin
      s := StringReplace(moneytxt,FormatSettings.ThousandSeparator,'',[rfReplaceAll]);
    end;
    {$ELSE}
    If pos(DecimalSeparator,moneytxt)<=0 then begin
      // No decimal separator, consider ThousandSeparator as a decimal separator
      s := StringReplace(moneytxt,ThousandSeparator,DecimalSeparator,[rfReplaceAll]);
    end else begin
      s := StringReplace(moneytxt,ThousandSeparator,'',[rfReplaceAll]);
    end;
    {$IFEND}

    money := Round( StrToFloat(s)*10000 );
    Result := true;
  Except
    result := false;
  end;
end;

class procedure TAccountComp.ValidsEC_OpenSSL_NID(list: TList);
begin
  list.Clear;
  list.Add(TObject(CT_NID_secp256k1)); // = 714
  list.Add(TObject(CT_NID_secp384r1)); // = 715
  list.Add(TObject(CT_NID_sect283k1)); // = 729
  list.Add(TObject(CT_NID_secp521r1)); // = 716
end;

end.
