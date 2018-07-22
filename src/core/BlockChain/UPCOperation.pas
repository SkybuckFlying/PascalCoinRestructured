unit UPCOperation;

interface

uses
  Classes, URawBytes, UOperationResume, UAccountPreviousBlockInfo, UPCSafeBoxTransaction;

type
  { TPCOperation }

  TPCOperation = Class
  Private
    Ftag: integer;
  Protected
    FPrevious_Signer_updated_block: Cardinal;
    FPrevious_Destination_updated_block : Cardinal;
    FPrevious_Seller_updated_block : Cardinal;
    FHasValidSignature : Boolean;
    FBufferedSha256 : TRawBytes;
  public
    constructor Create; virtual;
    destructor Destroy; override;

    // Skybuck: moved to here to make it accessable to TOperationsHashTree
    procedure InitializeData; virtual;
    function SaveOpToStream(Stream: TStream; SaveExtendedData : Boolean): Boolean; virtual; abstract;
    function LoadOpFromStream(Stream: TStream; LoadExtendedData : Boolean): Boolean; virtual; abstract;
    procedure FillOperationResume(Block : Cardinal; getInfoForAllAccounts : Boolean; Affected_account_number : Cardinal; var OperationResume : TOperationResume); virtual;

    // Skybuck: added write properties for TOperationHashTree
    Property Previous_Signer_updated_block : Cardinal read FPrevious_Signer_updated_block write FPrevious_Signer_updated_block; // deprecated
    Property Previous_Destination_updated_block : Cardinal read FPrevious_Destination_updated_block write FPrevious_Destination_updated_block; // deprecated
    Property Previous_Seller_updated_block : Cardinal read FPrevious_Seller_updated_block write FPrevious_Seller_updated_block; // deprecated


    function GetBufferForOpHash(UseProtocolV2 : Boolean): TRawBytes; virtual;
    function DoOperation(AccountPreviousUpdatedBlock : TAccountPreviousBlockInfo; AccountTransaction : TPCSafeBoxTransaction; var errors: AnsiString): Boolean; virtual; abstract;
    procedure AffectedAccounts(list : TList); virtual; abstract;
    class function OpType: Byte; virtual; abstract;
    Class Function OperationToOperationResume(Block : Cardinal; Operation : TPCOperation; getInfoForAllAccounts : Boolean; Affected_account_number : Cardinal; var OperationResume : TOperationResume) : Boolean; virtual;
    function OperationAmount : Int64; virtual; abstract;
    function OperationAmountByAccount(account : Cardinal) : Int64; virtual;
    function OperationFee: Int64; virtual; abstract;
    function OperationPayload : TRawBytes; virtual; abstract;
    function SignerAccount : Cardinal; virtual; abstract;
    procedure SignerAccounts(list : TList); virtual;
    function IsSignerAccount(account : Cardinal) : Boolean; virtual;
    function IsAffectedAccount(account : Cardinal) : Boolean; virtual;
    function DestinationAccount : Int64; virtual;
    function SellerAccount : Int64; virtual;
    function N_Operation : Cardinal; virtual; abstract;
    function GetAccountN_Operation(account : Cardinal) : Cardinal; virtual;
    Property tag : integer read Ftag Write Ftag;
    function SaveToNettransfer(Stream: TStream): Boolean;
    function LoadFromNettransfer(Stream: TStream): Boolean;
    function SaveToStorage(Stream: TStream): Boolean;
    function LoadFromStorage(Stream: TStream; LoadProtocolVersion : Word; APreviousUpdatedBlocks : TAccountPreviousBlockInfo): Boolean;
    Property HasValidSignature : Boolean read FHasValidSignature;
    Class function OperationHash_OLD(op : TPCOperation; Block : Cardinal) : TRawBytes;
    Class function OperationHashValid(op : TPCOperation; Block : Cardinal) : TRawBytes;
    class function IsValidOperationHash(const AOpHash : AnsiString) : Boolean;
    class function TryParseOperationHash(const AOpHash : AnsiString; var block, account, n_operation: Cardinal; var md160Hash : TRawBytes) : Boolean;
    Class function DecodeOperationHash(Const operationHash : TRawBytes; var block, account,n_operation : Cardinal; var md160Hash : TRawBytes) : Boolean;
    Class function EqualOperationHashes(Const operationHash1, operationHash2 : TRawBytes) : Boolean;
    Class function FinalOperationHashAsHexa(Const operationHash : TRawBytes) : AnsiString;
    class function OperationHashAsHexa(const operationHash : TRawBytes) : AnsiString;
    function Sha256 : TRawBytes;


    // Skybuck: properties added to make these accessable to TOperationHashTree
//    property HasValidSignature : Boolean read FHasValidSignature;
    property BufferedSha256 : TRawBytes read FBufferedSha256 write FBufferedSha256;

  End;

implementation

uses
  SysUtils, UCrypto, UBaseType, UConst, UOpTransaction, UAccountComp, UOpChangeAccountInfoType;

{ TPCOperation }

constructor TPCOperation.Create;
begin
  FHasValidSignature := False;
  FBufferedSha256:='';
  InitializeData;
end;

destructor TPCOperation.Destroy;
begin
  inherited Destroy;
end;

function TPCOperation.GetBufferForOpHash(UseProtocolV2: Boolean): TRawBytes;
Var ms : TMemoryStream;
begin
  // Protocol v2 change:
  // In previous builds (previous to 2.0) there was a distinct method to
  // save data for ophash and for calculate Sha256 value on merkle tree
  //
  // Starting in v2 we will use only 1 method to do both calcs
  // We will use "UseProtocolV2" bool value to indicate which method
  // want to calc.
  // Note: This method will be overrided by OpTransaction, OpChange and OpRecover only
  if (UseProtocolV2) then begin
    ms := TMemoryStream.Create;
    try
      SaveOpToStream(ms,False);
      ms.Position := 0;
      setlength(Result,ms.Size);
      ms.ReadBuffer(Result[1],ms.Size);
    finally
      ms.Free;
    end;
  end else Raise Exception.Create('ERROR DEV 20170426-1'); // This should never happen, if good coded
end;

procedure TPCOperation.SignerAccounts(list: TList);
begin
  list.Clear;
  list.Add(TObject(SignerAccount));
end;

class function TPCOperation.DecodeOperationHash(const operationHash: TRawBytes;
  var block, account, n_operation: Cardinal; var md160Hash : TRawBytes) : Boolean;
  { Decodes a previously generated OperationHash }
var ms : TMemoryStream;
begin
  Result := false;
  block :=0;
  account :=0;
  n_operation :=0;
  md160Hash:='';
  if length(operationHash)<>32 then exit;
  ms := TMemoryStream.Create;
  try
    ms.Write(operationHash[1],length(operationHash));
    ms.position := 0;
    ms.Read(block,4);
    ms.Read(account,4);
    ms.Read(n_operation,4);
    SetLength(md160Hash, 20);
    ms.ReadBuffer(md160Hash[1], 20);
    Result := true;
  finally
    ms.free;
  end;
end;

class function TPCOperation.IsValidOperationHash(const AOpHash : AnsiString) : Boolean;
var block, account, n_operation: Cardinal; md160Hash : TRawBytes;
begin
  Result := TryParseOperationHash(AOpHash, block, account, n_operation, md160Hash);
end;

class function TPCOperation.TryParseOperationHash(const AOpHash : AnsiString; var block, account, n_operation: Cardinal; var md160Hash : TRawBytes) : Boolean;
var
  ophash : TRawBytes;
begin
  ophash := TCrypto.HexaToRaw(trim(AOpHash));
  if Length(ophash) = 0 then
    Exit(false);
  If not TPCOperation.DecodeOperationHash(ophash,block,account,n_operation,md160Hash) then
    Exit(false);
  Result := true;
end;

class function TPCOperation.EqualOperationHashes(const operationHash1,operationHash2: TRawBytes): Boolean;
  // operationHash1 and operationHash2 must be in RAW format (Not hexadecimal string!)
var b0,b1,b2,r1,r2 : TRawBytes;
begin
  // First 4 bytes of OpHash are block number. If block=0 then is an unknown block, otherwise must match
  b1 := copy(operationHash1,1,4);
  b2 := copy(operationHash2,1,4);
  r1 := copy(operationHash1,5,length(operationHash1)-4);
  r2 := copy(operationHash2,5,length(operationHash2)-4);
  b0 := TCrypto.HexaToRaw('00000000');
  Result := (TBaseType.BinStrComp(r1,r2)=0) // Both right parts must be equal
    AND ((TBaseType.BinStrComp(b1,b0)=0) Or (TBaseType.BinStrComp(b2,b0)=0) Or (TBaseType.BinStrComp(b1,b2)=0)); // b is 0 value or b1=b2 (b = block number)
end;

class function TPCOperation.FinalOperationHashAsHexa(const operationHash: TRawBytes): AnsiString;
begin
  Result := TCrypto.ToHexaString(Copy(operationHash,5,28));
end;

class function TPCOperation.OperationHashAsHexa(const operationHash: TRawBytes): AnsiString;
begin
  Result := TCrypto.ToHexaString(operationHash);
end;

procedure TPCOperation.InitializeData;
begin
  FTag := 0;
  FPrevious_Signer_updated_block := 0;
  FPrevious_Destination_updated_block := 0;
  FPrevious_Seller_updated_block := 0;
  FHasValidSignature := false;
  FBufferedSha256:='';
end;

procedure TPCOperation.FillOperationResume(Block: Cardinal; getInfoForAllAccounts : Boolean; Affected_account_number: Cardinal; var OperationResume: TOperationResume);
begin
  //
end;

function TPCOperation.LoadFromNettransfer(Stream: TStream): Boolean;
begin
  Result := LoadOpFromStream(Stream, False);
end;

function TPCOperation.LoadFromStorage(Stream: TStream; LoadProtocolVersion:Word; APreviousUpdatedBlocks : TAccountPreviousBlockInfo): Boolean;
begin
  Result := false;
  If LoadOpFromStream(Stream, LoadProtocolVersion>=CT_PROTOCOL_2) then begin
    If LoadProtocolVersion<CT_PROTOCOL_3 then begin
      if Stream.Size - Stream.Position<8 then exit;
      Stream.Read(FPrevious_Signer_updated_block,Sizeof(FPrevious_Signer_updated_block));
      Stream.Read(FPrevious_Destination_updated_block,Sizeof(FPrevious_Destination_updated_block));
      if (LoadProtocolVersion=CT_PROTOCOL_2) then begin
        Stream.Read(FPrevious_Seller_updated_block,Sizeof(FPrevious_Seller_updated_block));
      end;
      if Assigned(APreviousUpdatedBlocks) then begin
        // Add to previous list!
        if SignerAccount>=0 then
          APreviousUpdatedBlocks.UpdateIfLower(SignerAccount,FPrevious_Signer_updated_block);
        if DestinationAccount>=0 then
          APreviousUpdatedBlocks.UpdateIfLower(DestinationAccount,FPrevious_Destination_updated_block);
        if SellerAccount>=0 then
          APreviousUpdatedBlocks.UpdateIfLower(SellerAccount,FPrevious_Seller_updated_block);
      end;
    end;
    Result := true;
  end;
end;

class function TPCOperation.OperationHash_OLD(op: TPCOperation; Block : Cardinal): TRawBytes;
  { OperationHash is a 32 bytes value.
    First 4 bytes (0..3) are Block in little endian
    Next 4 bytes (4..7) are Account in little endian
    Next 4 bytes (8..11) are N_Operation in little endian
    Next 20 bytes (12..31) are a RipeMD160 of the operation buffer to hash
    //
    This format is easy to undecode because include account and n_operation
   }
var ms : TMemoryStream;
  r : TRawBytes;
  _a,_o : Cardinal;
begin
  ms := TMemoryStream.Create;
  try
    ms.Write(Block,4);
    _a := op.SignerAccount;
    _o := op.N_Operation;
    ms.Write(_a,4);
    ms.Write(_o,4);
    // BUG IN PREVIOUS VERSIONS: (1.5.5 and prior)
    // Function DoRipeMD160 returned a 40 bytes value, because data was converted in hexa string!
    // So, here we used only first 20 bytes, and WHERE HEXA values, so only 16 diff values per 2 byte!
    ms.WriteBuffer(TCrypto.DoRipeMD160_HEXASTRING(op.GetBufferForOpHash(False))[1],20);
    SetLength(Result,ms.size);
    ms.Position:=0;
    ms.Read(Result[1],ms.size);
  finally
    ms.Free;
  end;
end;

class function TPCOperation.OperationHashValid(op: TPCOperation; Block : Cardinal): TRawBytes;
  { OperationHash is a 32 bytes value.
    First 4 bytes (0..3) are Block in little endian
    Next 4 bytes (4..7) are Account in little endian
    Next 4 bytes (8..11) are N_Operation in little endian
    Next 20 bytes (12..31) are a RipeMD160 of the SAME data used to calc Sha256
    //
    This format is easy to undecode because include account and n_operation
   }
var ms : TMemoryStream;
  r : TRawBytes;
  _a,_o : Cardinal;
begin
  ms := TMemoryStream.Create;
  try
    ms.Write(Block,4); // Save block (4 bytes)
    _a := op.SignerAccount;
    _o := op.N_Operation;
    ms.Write(_a,4);    // Save Account (4 bytes)
    ms.Write(_o,4);    // Save N_Operation (4 bytes)
    ms.WriteBuffer(TCrypto.DoRipeMD160AsRaw(op.GetBufferForOpHash(True))[1],20); // Calling GetBufferForOpHash(TRUE) is the same than data used for Sha256
    SetLength(Result,ms.size);
    ms.Position:=0;
    ms.Read(Result[1],ms.size);
  finally
    ms.Free;
  end;
end;

class function TPCOperation.OperationToOperationResume(Block : Cardinal; Operation: TPCOperation; getInfoForAllAccounts : Boolean; Affected_account_number: Cardinal; var OperationResume: TOperationResume): Boolean;
Var spayload : AnsiString;
  s : AnsiString;
begin
  OperationResume := CT_TOperationResume_NUL;
  OperationResume.Block:=Block;
  If Operation.SignerAccount=Affected_account_number then begin
    OperationResume.Fee := (-1)*Int64(Operation.OperationFee);
  end;
  OperationResume.AffectedAccount := Affected_account_number;
  OperationResume.OpType:=Operation.OpType;
  OperationResume.SignerAccount := Operation.SignerAccount;
  OperationResume.n_operation := Operation.N_Operation;
  Result := false;
  case Operation.OpType of
    CT_Op_Transaction : Begin
      // Assume that Operation is TOpTransaction
      OperationResume.DestAccount:=TOpTransaction(Operation).Data.target;
      if (TOpTransaction(Operation).Data.opTransactionStyle = transaction_with_auto_buy_account) then begin
        if TOpTransaction(Operation).Data.sender=Affected_account_number then begin
          OperationResume.OpSubtype := CT_OpSubtype_BuyTransactionBuyer;
          OperationResume.OperationTxt := 'Tx-Out (PASA '+TAccountComp.AccountNumberToAccountTxtNumber(TOpTransaction(Operation).Data.target)+' Purchase) '+TAccountComp.FormatMoney(TOpTransaction(Operation).Data.amount)+' PASC from '+
            TAccountComp.AccountNumberToAccountTxtNumber(TOpTransaction(Operation).Data.sender)+' to '+TAccountComp.AccountNumberToAccountTxtNumber(TOpTransaction(Operation).Data.target);
          If (TOpTransaction(Operation).Data.sender=TOpTransaction(Operation).Data.SellerAccount) then begin
            // Valid calc when sender is the same than seller
            OperationResume.Amount := (Int64(TOpTransaction(Operation).Data.amount) - (TOpTransaction(Operation).Data.AccountPrice)) * (-1);
          end else OperationResume.Amount := Int64(TOpTransaction(Operation).Data.amount) * (-1);
          Result := true;
        end else if TOpTransaction(Operation).Data.target=Affected_account_number then begin
          OperationResume.OpSubtype := CT_OpSubtype_BuyTransactionTarget;
          OperationResume.OperationTxt := 'Tx-In (PASA '+TAccountComp.AccountNumberToAccountTxtNumber(TOpTransaction(Operation).Data.target)+' Purchase) '+TAccountComp.FormatMoney(TOpTransaction(Operation).Data.amount)+' PASC from '+
            TAccountComp.AccountNumberToAccountTxtNumber(TOpTransaction(Operation).Data.sender)+' to '+TAccountComp.AccountNumberToAccountTxtNumber(TOpTransaction(Operation).Data.target);
          OperationResume.Amount := Int64(TOpTransaction(Operation).Data.amount) - Int64(TOpTransaction(Operation).Data.AccountPrice);
          OperationResume.Fee := 0;
          Result := true;
        end else if TOpTransaction(Operation).Data.SellerAccount=Affected_account_number then begin
          OperationResume.OpSubtype := CT_OpSubtype_BuyTransactionSeller;
          OperationResume.OperationTxt := 'Tx-In Sold account '+TAccountComp.AccountNumberToAccountTxtNumber(TOpTransaction(Operation).Data.target)+' price '+TAccountComp.FormatMoney(TOpTransaction(Operation).Data.AccountPrice)+' PASC';
          OperationResume.Amount := TOpTransaction(Operation).Data.AccountPrice;
          OperationResume.Fee := 0;
          Result := true;
        end else exit;
      end else begin
        if TOpTransaction(Operation).Data.sender=Affected_account_number then begin
          OperationResume.OpSubtype := CT_OpSubtype_TransactionSender;
          OperationResume.OperationTxt := 'Tx-Out '+TAccountComp.FormatMoney(TOpTransaction(Operation).Data.amount)+' PASC from '+TAccountComp.AccountNumberToAccountTxtNumber(TOpTransaction(Operation).Data.sender)+' to '+TAccountComp.AccountNumberToAccountTxtNumber(TOpTransaction(Operation).Data.target);
          OperationResume.Amount := Int64(TOpTransaction(Operation).Data.amount) * (-1);
          Result := true;
        end else if TOpTransaction(Operation).Data.target=Affected_account_number then begin
          OperationResume.OpSubtype := CT_OpSubtype_TransactionReceiver;
          OperationResume.OperationTxt := 'Tx-In '+TAccountComp.FormatMoney(TOpTransaction(Operation).Data.amount)+' PASC from '+TAccountComp.AccountNumberToAccountTxtNumber(TOpTransaction(Operation).Data.sender)+' to '+TAccountComp.AccountNumberToAccountTxtNumber(TOpTransaction(Operation).Data.target);
          OperationResume.Amount := TOpTransaction(Operation).Data.amount;
          OperationResume.Fee := 0;
          Result := true;
        end else exit;
      end;
    End;
    CT_Op_Changekey : Begin
      OperationResume.OpSubtype := CT_OpSubtype_ChangeKey;
      OperationResume.newKey := TOpChangeKey(Operation).Data.new_accountkey;
      OperationResume.DestAccount := TOpChangeKey(Operation).Data.account_target;
      OperationResume.OperationTxt := 'Change Key to '+TAccountComp.GetECInfoTxt( OperationResume.newKey.EC_OpenSSL_NID );
      Result := true;
    End;
    CT_Op_ChangeKeySigned : Begin
      OperationResume.OpSubtype := CT_OpSubtype_ChangeKeySigned;
      OperationResume.newKey := TOpChangeKeySigned(Operation).Data.new_accountkey;
      OperationResume.DestAccount := TOpChangeKeySigned(Operation).Data.account_target;
      OperationResume.OperationTxt := 'Change '+TAccountComp.AccountNumberToAccountTxtNumber(OperationResume.DestAccount)+' account key to '+TAccountComp.GetECInfoTxt( OperationResume.newKey.EC_OpenSSL_NID );
      Result := true;
    end;
    CT_Op_Recover : Begin
      OperationResume.OpSubtype := CT_OpSubtype_Recover;
      OperationResume.OperationTxt := 'Recover founds';
      Result := true;
    End;
    CT_Op_ListAccountForSale : Begin
      If TOpListAccount(Operation).IsPrivateSale then begin
        OperationResume.OpSubtype := CT_OpSubtype_ListAccountForPrivateSale;
        OperationResume.OperationTxt := 'List account '+TAccountComp.AccountNumberToAccountTxtNumber(TOpListAccount(Operation).Data.account_target)+' for private sale price '+
          TAccountComp.FormatMoney(TOpListAccount(Operation).Data.account_price)+' PASC pay to '+TAccountComp.AccountNumberToAccountTxtNumber(TOpListAccount(Operation).Data.account_to_pay);
      end else begin
        OperationResume.OpSubtype := CT_OpSubtype_ListAccountForPublicSale;
        OperationResume.OperationTxt := 'List account '+TAccountComp.AccountNumberToAccountTxtNumber(TOpListAccount(Operation).Data.account_target)+' for sale price '+
          TAccountComp.FormatMoney(TOpListAccount(Operation).Data.account_price)+' PASC pay to '+TAccountComp.AccountNumberToAccountTxtNumber(TOpListAccount(Operation).Data.account_to_pay);
      end;
      OperationResume.newKey := TOpListAccount(Operation).Data.new_public_key;
      OperationResume.SellerAccount := Operation.SellerAccount;
      Result := true;
    End;
    CT_Op_DelistAccount : Begin
      OperationResume.OpSubtype := CT_OpSubtype_DelistAccount;
      OperationResume.OperationTxt := 'Delist account '+TAccountComp.AccountNumberToAccountTxtNumber(TOpDelistAccountForSale(Operation).Data.account_target)+' for sale';
      Result := true;
    End;
    CT_Op_BuyAccount : Begin
      OperationResume.DestAccount:=TOpBuyAccount(Operation).Data.target;
      if TOpBuyAccount(Operation).Data.sender=Affected_account_number then begin
        OperationResume.OpSubtype := CT_OpSubtype_BuyAccountBuyer;
        OperationResume.OperationTxt := 'Buy account '+TAccountComp.AccountNumberToAccountTxtNumber(TOpBuyAccount(Operation).Data.target)+' for '+TAccountComp.FormatMoney(TOpBuyAccount(Operation).Data.AccountPrice)+' PASC';
        OperationResume.Amount := Int64(TOpBuyAccount(Operation).Data.amount) * (-1);
        Result := true;
      end else if TOpBuyAccount(Operation).Data.target=Affected_account_number then begin
        OperationResume.OpSubtype := CT_OpSubtype_BuyAccountTarget;
        OperationResume.OperationTxt := 'Purchased account '+TAccountComp.AccountNumberToAccountTxtNumber(TOpBuyAccount(Operation).Data.target)+' by '+
          TAccountComp.AccountNumberToAccountTxtNumber(TOpBuyAccount(Operation).Data.sender)+' for '+TAccountComp.FormatMoney(TOpBuyAccount(Operation).Data.AccountPrice)+' PASC';
        OperationResume.Amount := Int64(TOpBuyAccount(Operation).Data.amount) - Int64(TOpBuyAccount(Operation).Data.AccountPrice);
        OperationResume.Fee := 0;
        Result := true;
      end else if TOpBuyAccount(Operation).Data.SellerAccount=Affected_account_number then begin
        OperationResume.OpSubtype := CT_OpSubtype_BuyAccountSeller;
        OperationResume.OperationTxt := 'Sold account '+TAccountComp.AccountNumberToAccountTxtNumber(TOpBuyAccount(Operation).Data.target)+' by '+
          TAccountComp.AccountNumberToAccountTxtNumber(TOpBuyAccount(Operation).Data.sender)+' for '+TAccountComp.FormatMoney(TOpBuyAccount(Operation).Data.AccountPrice)+' PASC';
        OperationResume.Amount := TOpBuyAccount(Operation).Data.AccountPrice;
        OperationResume.Fee := 0;
        Result := true;
      end else exit;
    End;
    CT_Op_ChangeAccountInfo : Begin
      OperationResume.DestAccount := Operation.DestinationAccount;
      s := '';
      if (ait_public_key in TOpChangeAccountInfo(Operation).Data.changes_type) then begin
        s := 'key';
      end;
      if (ait_account_name in TOpChangeAccountInfo(Operation).Data.changes_type) then begin
        if s<>'' then s:=s+',';
        s := s + 'name';
      end;
      if (ait_account_type in TOpChangeAccountInfo(Operation).Data.changes_type) then begin
        if s<>'' then s:=s+',';
        s := s + 'type';
      end;
      OperationResume.OperationTxt:= 'Changed '+s+' of account '+TAccountComp.AccountNumberToAccountTxtNumber(Operation.DestinationAccount);
      OperationResume.OpSubtype:=CT_OpSubtype_ChangeAccountInfo;
      Result := True;
    end;
    CT_Op_MultiOperation : Begin
      OperationResume.isMultiOperation:=True;
      OperationResume.OperationTxt := Operation.ToString;
      OperationResume.Amount := Operation.OperationAmountByAccount(Affected_account_number);
      OperationResume.Fee := 0;
      Result := True;
    end
  else Exit;
  end;
  OperationResume.OriginalPayload := Operation.OperationPayload;
  If TCrypto.IsHumanReadable(OperationResume.OriginalPayload) then OperationResume.PrintablePayload := OperationResume.OriginalPayload
  else OperationResume.PrintablePayload := TCrypto.ToHexaString(OperationResume.OriginalPayload);
  OperationResume.OperationHash:=TPCOperation.OperationHashValid(Operation,Block);
  if (Block>0) And (Block<CT_Protocol_Upgrade_v2_MinBlock) then begin
    OperationResume.OperationHash_OLD:=TPCOperation.OperationHash_OLD(Operation,Block);
  end;
  OperationResume.valid := true;
  Operation.FillOperationResume(Block,getInfoForAllAccounts,Affected_account_number,OperationResume);
end;

function TPCOperation.IsSignerAccount(account: Cardinal): Boolean;
begin
  Result := SignerAccount = account;
end;

function TPCOperation.IsAffectedAccount(account: Cardinal): Boolean;
Var l : TList;
begin
  l := TList.Create;
  Try
    AffectedAccounts(l);
    Result := (l.IndexOf(TObject(account))>=0);
  finally
    l.Free;
  end;
end;

function TPCOperation.DestinationAccount: Int64;
begin
  Result := -1;
end;

function TPCOperation.SellerAccount: Int64;
begin
  Result := -1;
end;

function TPCOperation.GetAccountN_Operation(account: Cardinal): Cardinal;
begin
  If (SignerAccount = account) then Result := N_Operation
  else Result := 0;
end;

function TPCOperation.SaveToNettransfer(Stream: TStream): Boolean;
begin
  Result := SaveOpToStream(Stream,False);
end;

function TPCOperation.SaveToStorage(Stream: TStream): Boolean;
begin
  Result := SaveOpToStream(Stream,True);
end;

function TPCOperation.Sha256: TRawBytes;
begin
  If Length(FBufferedSha256)=0 then begin
    FBufferedSha256 := TCrypto.DoSha256(GetBufferForOpHash(true));
  end;
  Result := FBufferedSha256;
end;

function TPCOperation.OperationAmountByAccount(account: Cardinal): Int64;
begin
  Result := 0;
end;

end.
