unit UPCOperationsComp;

interface

uses
  Classes, UPCSafeBoxTransaction, UOperationBlock, UOperationsHashTree, URawBytes, UThread, UAccountPreviousBlockInfo, UPCOperation, UAccountKey, UOperationResume, UPCOperationClass;

type
  { TPCOperationsComp }
  TPCOperationsComp = Class(TComponent)
  private
    {$IF DEFINED(CIRCULAR_REFERENCE_PROBLEM)}
    FBank: TPCBank;
    {$ENDIF}
    FSafeBoxTransaction : TPCSafeBoxTransaction;
    FOperationBlock: TOperationBlock;
    FOperationsHashTree : TOperationsHashTree;
    FDigest_Part1 : TRawBytes;
    FDigest_Part2_Payload : TRawBytes;
    FDigest_Part3 : TRawBytes;
    FIsOnlyOperationBlock: Boolean;
    FStreamPoW : TMemoryStream;
    FDisableds : Integer;
    FOperationsLock : TPCCriticalSection;
    FPreviousUpdatedBlocks : TAccountPreviousBlockInfo; // New Protocol V3 struct to store previous updated blocks
    function GetOperation(index: Integer): TPCOperation;
    {$IF DEFINED(CIRCULAR_REFERENCE_PROBLEM)}
    procedure SetBank(const value: TPCBank);
    {$ENDIF}
    procedure SetnOnce(const value: Cardinal);
    procedure Settimestamp(const value: Cardinal);
    function GetnOnce: Cardinal;
    function Gettimestamp: Cardinal;
    procedure SetAccountKey(const value: TAccountKey);
    function GetAccountKey: TAccountKey;
    Procedure Calc_Digest_Parts;
    Procedure Calc_Digest_Part3;
    Procedure CalcProofOfWork(fullcalculation : Boolean; var PoW: TRawBytes);
    function GetBlockPayload: TRawBytes;
    procedure SetBlockPayload(const Value: TRawBytes);
    procedure OnOperationsHashTreeChanged(Sender : TObject);
  protected
    procedure Notification(AComponent: TComponent; Operation: TOperation); Override;
    function SaveBlockToStreamExt(save_only_OperationBlock : Boolean; Stream: TStream; SaveToStorage : Boolean): Boolean;
    function LoadBlockFromStreamExt(Stream: TStream; LoadingFromStorage : Boolean; var errors: AnsiString): Boolean;
  public
    Constructor Create(AOwner: TComponent); Override;
    Destructor Destroy; Override;
    Procedure CopyFromExceptAddressKey(Operations : TPCOperationsComp);
    Procedure CopyFrom(Operations : TPCOperationsComp);
    Function AddOperation(Execute : Boolean; op: TPCOperation; var errors: AnsiString): Boolean;
    Function AddOperations(operations: TOperationsHashTree; var errors: AnsiString): Integer;
    Property Operation[index: Integer]: TPCOperation read GetOperation;
    {$IF DEFINED(CIRCULAR_REFERENCE_PROBLEM)}
    Property bank: TPCBank read FBank write SetBank;
    {$ENDIF}
    Procedure Clear(DeleteOperations : Boolean);
    Function Count: Integer;
    Property OperationBlock: TOperationBlock read FOperationBlock;
    Class Function OperationBlockToText(const OperationBlock: TOperationBlock) : AnsiString;
    Class Function SaveOperationBlockToStream(Const OperationBlock: TOperationBlock; Stream: TStream) : Boolean;
    Property AccountKey: TAccountKey read GetAccountKey write SetAccountKey;
    Property nonce: Cardinal read GetnOnce write SetnOnce;
    Property timestamp: Cardinal read Gettimestamp write Settimestamp;
    Property BlockPayload : TRawBytes read GetBlockPayload write SetBlockPayload;
    function Update_And_RecalcPOW(newNOnce, newTimestamp : Cardinal; newBlockPayload : TRawBytes) : Boolean;
    procedure UpdateTimestamp;
    function SaveBlockToStorage(Stream: TStream): Boolean;
    function SaveBlockToStream(save_only_OperationBlock : Boolean; Stream: TStream): Boolean;
    function LoadBlockFromStorage(Stream: TStream; var errors: AnsiString): Boolean;
    function LoadBlockFromStream(Stream: TStream; var errors: AnsiString): Boolean;
    //
    Function GetMinerRewardPseudoOperation : TOperationResume;
    Function ValidateOperationBlock(var errors : AnsiString) : Boolean;
    Property IsOnlyOperationBlock : Boolean read FIsOnlyOperationBlock;
    Procedure Lock;
    Procedure Unlock;
    //
    Procedure SanitizeOperations;

    Class Function RegisterOperationClass(OpClass: TPCOperationClass): Boolean;
    Class Function IndexOfOperationClass(OpClass: TPCOperationClass): Integer;
    Class Function IndexOfOperationClassByOpType(OpType: Cardinal): Integer;
    Class Function GetOperationClassByOpType(OpType: Cardinal): TPCOperationClass;
    Class Function GetFirstBlock : TOperationBlock;
    Class Function EqualsOperationBlock(Const OperationBlock1,OperationBlock2 : TOperationBlock):Boolean;
    //
    Property SafeBoxTransaction : TPCSafeBoxTransaction read FSafeBoxTransaction;
    Property OperationsHashTree : TOperationsHashTree read FOperationsHashTree;
    Property PoW_Digest_Part1 : TRawBytes read FDigest_Part1;
    Property PoW_Digest_Part2_Payload : TRawBytes read FDigest_Part2_Payload;
    Property PoW_Digest_Part3 : TRawBytes read FDigest_Part3;
    //
    Property PreviousUpdatedBlocks : TAccountPreviousBlockInfo read FPreviousUpdatedBlocks; // New Protocol V3 struct to store previous updated blocks
  End;

  // *** Skybuck: Super experimental and probably flawed code, going to do a git commit because here/these circular refences is where things start to get tricky ! ***
//  TPCBank = class

//  end;


implementation

uses
  UPCBank, SysUtils, UCrypto, UPascalCoinProtocol, UTime, UConst, UAccountComp, UStreamOp, ULog, UBaseType;

{ TPCOperationsComp }

function TPCOperationsComp.AddOperation(Execute: Boolean; op: TPCOperation; var errors: AnsiString): Boolean;
Begin
  Lock;
  Try
    errors := '';
    Result := False;
    if Execute then begin
      {$IF DEFINED(CIRCULAR_REFERENCE_PROBLEM)}
      if (FBank = Nil) then begin
        errors := 'No Bank';
        exit;
      end;
      if (FBank.BlocksCount<>OperationBlock.block) then begin
        errors := 'Bank blockcount<>OperationBlock.Block';
        exit;
      end;
      {$ENDIF}
      // Only process when in current address, prevent do it when reading operations from file
      Result := op.DoOperation(FPreviousUpdatedBlocks, FSafeBoxTransaction, errors);
    end else Result := true;
    if Result then begin
      FOperationsHashTree.AddOperationToHashTree(op);
      FOperationBlock.fee := FOperationBlock.fee + op.OperationFee;
      FOperationBlock.operations_hash := FOperationsHashTree.HashTree;
      if FDisableds<=0 then Calc_Digest_Parts;
    end;
  finally
    Unlock;
  end;
End;


function TPCOperationsComp.AddOperations(operations: TOperationsHashTree; var errors: AnsiString): Integer;
Var i : Integer;
  e : AnsiString;
begin
  Lock;
  try
    Result := 0;
    errors := '';
    if operations=FOperationsHashTree then exit;
    inc(FDisableds);
    try
      for i := 0 to operations.OperationsCount - 1 do begin
        if not AddOperation(true,operations.GetOperation(i),e) then begin
          if (errors<>'') then errors := errors+' ';
          errors := errors + 'Op'+inttostr(i+1)+'/'+inttostr(operations.OperationsCount)+':'+e;
        end else inc(Result);
      end;
    finally
      Dec(FDisableds);
      Calc_Digest_Parts;
    end;
  finally
    Unlock;
  end;
end;

procedure TPCOperationsComp.CalcProofOfWork(fullcalculation: Boolean; var PoW: TRawBytes);
begin
  if fullcalculation then begin
    Calc_Digest_Parts;
  end;
  FStreamPoW.Position := 0;
  FStreamPoW.WriteBuffer(FDigest_Part1[1],length(FDigest_Part1));
  FStreamPoW.WriteBuffer(FDigest_Part2_Payload[1],length(FDigest_Part2_Payload));
  FStreamPoW.WriteBuffer(FDigest_Part3[1],length(FDigest_Part3));
  FStreamPoW.Write(FOperationBlock.timestamp,4);
  FStreamPoW.Write(FOperationBlock.nonce,4);
  TCrypto.DoDoubleSha256(FStreamPoW.Memory,length(FDigest_Part1)+length(FDigest_Part2_Payload)+length(FDigest_Part3)+8,PoW);
end;

procedure TPCOperationsComp.Calc_Digest_Parts;
begin
  TPascalCoinProtocol.CalcProofOfWork_Part1(FOperationBlock,FDigest_Part1);
  FDigest_Part2_Payload := FOperationBlock.block_payload;
  Calc_Digest_Part3;
end;

procedure TPCOperationsComp.Calc_Digest_Part3;
begin
  FOperationBlock.operations_hash:=FOperationsHashTree.HashTree;
  TPascalCoinProtocol.CalcProofOfWork_Part3(FOperationBlock,FDigest_Part3);
end;

procedure TPCOperationsComp.Clear(DeleteOperations : Boolean);
begin
  Lock;
  Try
    if DeleteOperations then begin
      FOperationsHashTree.ClearHastThree;
      FPreviousUpdatedBlocks.Clear;
      if Assigned(FSafeBoxTransaction) then
        FSafeBoxTransaction.CleanTransaction;
    end;

    // Note:
    // This function does not initializes "account_key" nor "block_payload" fields

    FOperationBlock.timestamp := UnivDateTimeToUnix(DateTime2UnivDateTime(now));

    {$IF DEFINED(CIRCULAR_REFERENCE_PROBLEM)}
    if Assigned(FBank) then begin
      FOperationBlock.protocol_version := FBank.SafeBox.CurrentProtocol;
      If (FOperationBlock.protocol_version=CT_PROTOCOL_1) And (FBank.SafeBox.CanUpgradeToProtocol(CT_PROTOCOL_2)) then begin
        FOperationBlock.protocol_version := CT_PROTOCOL_2; // If minting... upgrade to Protocol 2
      end else if (FOperationBlock.protocol_version=CT_PROTOCOL_2) And (FBank.SafeBox.CanUpgradeToProtocol(CT_PROTOCOL_3)) then begin
        FOperationBlock.protocol_version := CT_PROTOCOL_3; // If minting... upgrade to Protocol 3
      end;
      FOperationBlock.block := FBank.BlocksCount;
      FOperationBlock.reward := TPascalCoinProtocol.GetRewardForNewLine(FBank.BlocksCount);
      FOperationBlock.compact_target := FBank.Safebox.GetActualCompactTargetHash(FOperationBlock.protocol_version);
      FOperationBlock.initial_safe_box_hash := FBank.SafeBox.SafeBoxHash;
      If FBank.LastOperationBlock.timestamp>FOperationBlock.timestamp then
        FOperationBlock.timestamp := FBank.LastOperationBlock.timestamp;
    end else begin
      FOperationBlock.block := 0;
      FOperationBlock.reward := TPascalCoinProtocol.GetRewardForNewLine(0);
      FOperationBlock.compact_target := CT_MinCompactTarget;
      FOperationBlock.initial_safe_box_hash := TCrypto.DoSha256(CT_Genesis_Magic_String_For_Old_Block_Hash); // Nothing for first line
      FOperationBlock.protocol_version := CT_PROTOCOL_1;
    end;
    {$ENDIF}

    FOperationBlock.operations_hash := FOperationsHashTree.HashTree;
    FOperationBlock.fee := 0;
    FOperationBlock.nonce := 0;
    FOperationBlock.proof_of_work := '';
    FOperationBlock.protocol_available := CT_BlockChain_Protocol_Available;
    FIsOnlyOperationBlock := false;
  Finally
    try
      CalcProofOfWork(true,FOperationBlock.proof_of_work);
    finally
      Unlock;
    end;
  End;
end;

procedure TPCOperationsComp.CopyFrom(Operations: TPCOperationsComp);
begin
  if Self=Operations then exit;
  Lock;
  Operations.Lock;
  Try
    FOperationBlock := Operations.FOperationBlock;
    FIsOnlyOperationBlock := Operations.FIsOnlyOperationBlock;
    FOperationsHashTree.CopyFromHashTree(Operations.FOperationsHashTree);
    if Assigned(FSafeBoxTransaction) And Assigned(Operations.FSafeBoxTransaction) then begin
      FSafeBoxTransaction.CopyFrom(Operations.FSafeBoxTransaction);
    end;
    FPreviousUpdatedBlocks.CopyFrom(Operations.FPreviousUpdatedBlocks);
    FDigest_Part1 := Operations.FDigest_Part1;
    FDigest_Part2_Payload := Operations.FDigest_Part2_Payload;
    FDigest_Part3 := Operations.FDigest_Part3;
  finally
    Operations.Unlock;
    Unlock;
  end;
end;

procedure TPCOperationsComp.CopyFromExceptAddressKey(Operations: TPCOperationsComp);
var lastopb : TOperationBlock;
begin
  Lock;
  Try
    if Self=Operations then exit;
    lastopb := FOperationBlock;
    FOperationBlock := Operations.FOperationBlock;
    FOperationBlock.account_key := lastopb.account_key; // Except AddressKey

    {$IF DEFINED(CIRCULAR_REFERENCE_PROBLEM)}
    FOperationBlock.compact_target := FBank.Safebox.GetActualCompactTargetHash(FOperationBlock.protocol_version);
    {$ENDIF}

    FIsOnlyOperationBlock := Operations.FIsOnlyOperationBlock;
    FOperationsHashTree.CopyFromHashTree(Operations.FOperationsHashTree);
    FOperationBlock.operations_hash := FOperationsHashTree.HashTree;
    if Assigned(FSafeBoxTransaction) And Assigned(Operations.FSafeBoxTransaction) then begin
      FSafeBoxTransaction.CopyFrom(Operations.FSafeBoxTransaction);
    end;
    FPreviousUpdatedBlocks.CopyFrom(Operations.FPreviousUpdatedBlocks);
    // Recalc all
    CalcProofOfWork(true,FOperationBlock.proof_of_work);
  finally
    Unlock;
  end;
end;

function TPCOperationsComp.Count: Integer;
begin
  Result := FOperationsHashTree.OperationsCount;
end;

constructor TPCOperationsComp.Create(AOwner: TComponent);
begin
  inherited Create(AOwner);
  FOperationsLock := TPCCriticalSection.Create('TPCOperationsComp_OPERATIONSLOCK');
  FDisableds := 0;
  FStreamPoW := TMemoryStream.Create;
  FStreamPoW.Position := 0;
  FOperationsHashTree := TOperationsHashTree.Create;
  FOperationsHashTree.OnChanged:= OnOperationsHashTreeChanged;

  {$IF DEFINED(CIRCULAR_REFERENCE_PROBLEM)}
  FBank := Nil;
  {$ENDIF}

  FOperationBlock := GetFirstBlock;
  FSafeBoxTransaction := Nil;
  FPreviousUpdatedBlocks := TAccountPreviousBlockInfo.Create;

  {$IF DEFINED(CIRCULAR_REFERENCE_PROBLEM)}
  if Assigned(AOwner) And (AOwner is TPCBank) then begin
    SetBank( TPCBank(AOwner) );
  end else Clear(true);
  {$ENDIF}
end;

destructor TPCOperationsComp.Destroy;
begin
  FOperationsLock.Acquire;
  try
    Clear(true);
    FreeAndNil(FOperationsHashTree);
    if Assigned(FSafeBoxTransaction) then begin
      FreeAndNil(FSafeBoxTransaction);
    end;
    FreeAndNil(FStreamPoW);
    FreeAndNil(FPreviousUpdatedBlocks);
  finally
    FreeAndNil(FOperationsLock);
  end;
  inherited;
end;

class function TPCOperationsComp.EqualsOperationBlock(const OperationBlock1,
  OperationBlock2: TOperationBlock): Boolean;
begin

  Result := (OperationBlock1.block=OperationBlock2.block)
           And (TAccountComp.EqualAccountKeys(OperationBlock1.account_key,OperationBlock2.account_key))
           And (OperationBlock1.reward=OperationBlock2.reward)
           And (OperationBlock1.fee=OperationBlock2.fee)
           And (OperationBlock1.protocol_version=OperationBlock2.protocol_version)
           And (OperationBlock1.protocol_available=OperationBlock2.protocol_available)
           And (OperationBlock1.timestamp=OperationBlock2.timestamp)
           And (OperationBlock1.compact_target=OperationBlock2.compact_target)
           And (OperationBlock1.nonce=OperationBlock2.nonce)
           And (OperationBlock1.block_payload=OperationBlock2.block_payload)
           And (OperationBlock1.initial_safe_box_hash=OperationBlock2.initial_safe_box_hash)
           And (OperationBlock1.operations_hash=OperationBlock2.operations_hash)
           And (OperationBlock1.proof_of_work=OperationBlock2.proof_of_work);
end;

function TPCOperationsComp.GetAccountKey: TAccountKey;
begin
  Result := FOperationBlock.account_key;
end;

function TPCOperationsComp.GetBlockPayload: TRawBytes;
begin
  Result := FOperationBlock.block_payload;
end;

class function TPCOperationsComp.GetFirstBlock: TOperationBlock;
begin
  Result := CT_OperationBlock_NUL;
end;

function TPCOperationsComp.GetnOnce: Cardinal;
begin
  Result := FOperationBlock.nonce;
end;

function TPCOperationsComp.GetOperation(index: Integer): TPCOperation;
begin
  Result := FOperationsHashTree.GetOperation(index);
end;

class function TPCOperationsComp.GetOperationClassByOpType(OpType: Cardinal): TPCOperationClass;
Var i : Integer;
begin
  i := IndexOfOperationClassByOpType(OpType);
  if i<0 then result := Nil
  else Result := TPCOperationClass( _OperationsClass[i] );
end;

function TPCOperationsComp.Gettimestamp: Cardinal;
begin
  Result := FOperationBlock.timestamp;
end;


class function TPCOperationsComp.IndexOfOperationClass(OpClass: TPCOperationClass): Integer;
begin
  for Result := low(_OperationsClass) to high(_OperationsClass) do
  begin
    if (_OperationsClass[Result] = OpClass) then
      exit;
  end;
  Result := -1;
end;

class function TPCOperationsComp.IndexOfOperationClassByOpType(OpType: Cardinal): Integer;
begin
  for Result := low(_OperationsClass) to high(_OperationsClass) do
  begin
    if (_OperationsClass[Result].OpType = OpType) then
      exit;
  end;
  Result := -1;
end;

function TPCOperationsComp.LoadBlockFromStorage(Stream: TStream; var errors: AnsiString): Boolean;
begin
  Result := LoadBlockFromStreamExt(Stream,true,errors);
end;

function TPCOperationsComp.LoadBlockFromStream(Stream: TStream; var errors: AnsiString): Boolean;
begin
  Result := LoadBlockFromStreamExt(Stream,false,errors);
end;

function TPCOperationsComp.LoadBlockFromStreamExt(Stream: TStream; LoadingFromStorage: Boolean; var errors: AnsiString): Boolean;
Var i : Integer;
  lastfee : UInt64;
  soob : Byte;
  m: AnsiString;
  load_protocol_version : Word;
begin
  Lock;
  Try
    Clear(true);
    Result := False;
    //
    errors := '';
    if (Stream.Size - Stream.Position < 5) then begin
      errors := 'Invalid protocol structure. Check application version!';
      exit;
    end;
    soob := 255;
    Stream.Read(soob,1);
    // About soob var:
    // In build prior to 1.0.4 soob only can have 2 values: 0 or 1
    // In build 1.0.4 soob can has 2 more values: 2 or 3
    // In build 2.0 soob can has 1 more value: 4
    // In build 3.0 soob can hast value: 5
    // In future, old values 0 and 1 will no longer be used!
    // - Value 0 and 2 means that contains also operations
    // - Value 1 and 3 means that only contains operationblock info
    // - Value 2 and 3 means that contains protocol info prior to block number
    // - Value 4 means that is loading from storage using protocol v2 (so, includes always operations)
    // - Value 5 means that is loading from storage using TAccountPreviousBlockInfo
    load_protocol_version := CT_PROTOCOL_1;
    if (soob in [0,2]) then FIsOnlyOperationBlock:=false
    else if (soob in [1,3]) then FIsOnlyOperationBlock:=true
    else if (soob in [4]) then begin
      FIsOnlyOperationBlock:=false;
      load_protocol_version := CT_PROTOCOL_2;
    end else if (soob in [5]) then begin
      FIsOnlyOperationBlock:=False;
      load_protocol_version := CT_PROTOCOL_3;
    end else begin
      errors := 'Invalid value in protocol header! Found:'+inttostr(soob)+' - Check if your application version is Ok';
      exit;
    end;

    if (soob in [2,3,4,5]) then begin
      Stream.Read(FOperationBlock.protocol_version, Sizeof(FOperationBlock.protocol_version));
      Stream.Read(FOperationBlock.protocol_available, Sizeof(FOperationBlock.protocol_available));
    end else begin
      // We assume that protocol_version is 1 and protocol_available is 0
      FOperationBlock.protocol_version := 1;
      FOperationBlock.protocol_available := 0;
    end;

    if Stream.Read(FOperationBlock.block, Sizeof(FOperationBlock.block))<0 then exit;

    if TStreamOp.ReadAnsiString(Stream, m) < 0 then exit;
    FOperationBlock.account_key := TAccountComp.RawString2Accountkey(m);
    if Stream.Read(FOperationBlock.reward, Sizeof(FOperationBlock.reward)) < 0 then exit;
    if Stream.Read(FOperationBlock.fee, Sizeof(FOperationBlock.fee)) < 0 then exit;
    if Stream.Read(FOperationBlock.timestamp, Sizeof(FOperationBlock.timestamp)) < 0 then exit;
    if Stream.Read(FOperationBlock.compact_target, Sizeof(FOperationBlock.compact_target)) < 0 then exit;
    if Stream.Read(FOperationBlock.nonce, Sizeof(FOperationBlock.nonce)) < 0 then exit;
    if TStreamOp.ReadAnsiString(Stream, FOperationBlock.block_payload) < 0 then exit;
    if TStreamOp.ReadAnsiString(Stream, FOperationBlock.initial_safe_box_hash) < 0 then exit;
    if TStreamOp.ReadAnsiString(Stream, FOperationBlock.operations_hash) < 0 then exit;
    if TStreamOp.ReadAnsiString(Stream, FOperationBlock.proof_of_work) < 0 then exit;
    If FIsOnlyOperationBlock then begin
      Result := true;
      exit;
    end;
    // Fee will be calculated for each operation. Set it to 0 and check later for integrity
    lastfee := OperationBlock.fee;
    FOperationBlock.fee := 0;
    Result := FOperationsHashTree.LoadOperationsHashTreeFromStream(Stream,LoadingFromStorage,load_protocol_version,FPreviousUpdatedBlocks,errors);
    if not Result then begin
      exit;
    end;
    If load_protocol_version>=CT_PROTOCOL_3 then begin
      Result := FPreviousUpdatedBlocks.LoadFromStream(Stream);
      If Not Result then begin
        errors := 'Invalid PreviousUpdatedBlock stream';
        Exit;
      end;
    end;
    //
    FOperationBlock.fee := FOperationsHashTree.TotalFee;
    FOperationBlock.operations_hash := FOperationsHashTree.HashTree;
    Calc_Digest_Parts;
    // Validation control:
    if (lastfee<>OperationBlock.fee) then begin
      errors := 'Corrupted operations fee old:'+inttostr(lastfee)+' new:'+inttostr(OperationBlock.fee);
      for i := 0 to FOperationsHashTree.OperationsCount - 1 do begin
        errors := errors + ' Op'+inttostr(i+1)+':'+FOperationsHashTree.GetOperation(i).ToString;
      end;
      Result := false;
      exit;
    end;
    Result := true;
  finally
    Unlock;
  end;
end;

procedure TPCOperationsComp.Notification(AComponent: TComponent;
  Operation: TOperation);
begin
  inherited;
  if (Operation = opRemove) then begin

    {$IF DEFINED(CIRCULAR_REFERENCE_PROBLEM)}
    if AComponent = FBank then begin
      FBank := Nil;
      FreeAndNil(FSafeBoxTransaction);
    end;
    {$ENDIF}
  end;
end;

class function TPCOperationsComp.OperationBlockToText(const OperationBlock: TOperationBlock): AnsiString;
begin
  Result := Format('Block:%d Timestamp:%d Reward:%d Fee:%d Target:%d PoW:%s Payload:%s Nonce:%d OperationsHash:%s SBH:%s',[operationBlock.block,
    operationblock.timestamp,operationblock.reward,operationblock.fee, OperationBlock.compact_target, TCrypto.ToHexaString(operationblock.proof_of_work),
    OperationBlock.block_payload,OperationBlock.nonce,TCrypto.ToHexaString(OperationBlock.operations_hash),
    TCrypto.ToHexaString(OperationBlock.initial_safe_box_hash)]);
end;

class function TPCOperationsComp.RegisterOperationClass(OpClass: TPCOperationClass): Boolean;
Var
  i: Integer;
begin
  i := IndexOfOperationClass(OpClass);
  if i >= 0 then
    exit;
  SetLength(_OperationsClass, Length(_OperationsClass) + 1);
  _OperationsClass[ high(_OperationsClass)] := OpClass;
end;

procedure TPCOperationsComp.SanitizeOperations;
  { This function check operationblock with bank and updates itself if necessary
    Then checks if operations are ok, and deletes old ones.
    Finally calculates new operation pow
    It's used when a new account has beed found by other chanels (miners o nodes...)
    }
Var i,n,lastn : Integer;
  op : TPCOperation;
  errors : AnsiString;
  aux,aux2 : TOperationsHashTree;
begin
  Lock;
  Try
    FOperationBlock.timestamp := UnivDateTimeToUnix(DateTime2UnivDateTime(now));

    {$IF DEFINED(CIRCULAR_REFERENCE_PROBLEM)}
    if Assigned(FBank) then begin
      FOperationBlock.protocol_version := FBank.SafeBox.CurrentProtocol;
      If (FOperationBlock.protocol_version=CT_PROTOCOL_1) And (FBank.SafeBox.CanUpgradeToProtocol(CT_PROTOCOL_2)) then begin
        TLog.NewLog(ltinfo,ClassName,'New miner protocol version to 2 at sanitize');
        FOperationBlock.protocol_version := CT_PROTOCOL_2;
      end else if (FOperationBlock.protocol_version=CT_PROTOCOL_2) And (FBank.SafeBox.CanUpgradeToProtocol(CT_PROTOCOL_3)) then begin
        TLog.NewLog(ltinfo,ClassName,'New miner protocol version to 3 at sanitize');
        FOperationBlock.protocol_version := CT_PROTOCOL_3;
      end;
      FOperationBlock.block := FBank.BlocksCount;
      FOperationBlock.reward := TPascalCoinProtocol.GetRewardForNewLine(FBank.BlocksCount);
      FOperationBlock.compact_target := FBank.SafeBox.GetActualCompactTargetHash(FOperationBlock.protocol_version);
      FOperationBlock.initial_safe_box_hash := FBank.SafeBox.SafeBoxHash;
      If FBank.LastOperationBlock.timestamp>FOperationBlock.timestamp then
        FOperationBlock.timestamp := FBank.LastOperationBlock.timestamp;
    end else begin
      FOperationBlock.block := 0;
      FOperationBlock.reward := TPascalCoinProtocol.GetRewardForNewLine(0);
      FOperationBlock.compact_target := CT_MinCompactTarget;
      FOperationBlock.initial_safe_box_hash := TCrypto.DoSha256(CT_Genesis_Magic_String_For_Old_Block_Hash);
      FOperationBlock.protocol_version := CT_PROTOCOL_1;
    end;
    {$ENDIF}

    FOperationBlock.proof_of_work := '';
    FOperationBlock.protocol_available := CT_BlockChain_Protocol_Available;
    n := 0;
    FOperationBlock.fee := 0;
    //
    SafeBoxTransaction.CleanTransaction;
    FPreviousUpdatedBlocks.Clear;
    aux := TOperationsHashTree.Create;
    Try
      lastn := FOperationsHashTree.OperationsCount;
      for i:=0 to lastn-1 do begin
        op := FOperationsHashTree.GetOperation(i);
        if (op.DoOperation(FPreviousUpdatedBlocks, SafeBoxTransaction,errors)) then begin
          inc(n);
          aux.AddOperationToHashTree(op);
          FOperationBlock.fee := FOperationBlock.fee + op.OperationFee;
          {$IFDEF HIGHLOG}TLog.NewLog(ltdebug,Classname,'Sanitizing (pos:'+inttostr(i+1)+'/'+inttostr(lastn)+'): '+op.ToString){$ENDIF};
        end;
      end;
    Finally
      aux2 := FOperationsHashTree;
      FOperationsHashTree := aux;
      aux2.Free;
      FOperationBlock.operations_hash := FOperationsHashTree.HashTree;
    End;
  Finally
    CalcProofOfWork(true,FOperationBlock.proof_of_work);
    Unlock;
  End;
  if (n>0) then begin
    TLog.NewLog(ltdebug,Classname,Format('Sanitize operations (before %d - after %d)',[lastn,n]));
  end;
end;

function TPCOperationsComp.SaveBlockToStorage(Stream: TStream): Boolean;
begin
  Result := SaveBlockToStreamExt(false,Stream,true);
end;

function TPCOperationsComp.SaveBlockToStream(save_only_OperationBlock : Boolean; Stream: TStream): Boolean;
begin
  Result := SaveBlockToStreamExt(save_only_OperationBlock,Stream,false);
end;

function TPCOperationsComp.SaveBlockToStreamExt(save_only_OperationBlock: Boolean; Stream: TStream; SaveToStorage: Boolean): Boolean;
Var soob : Byte;
begin
  Lock;
  Try
    if save_only_OperationBlock then begin
      {Old versions:
      if (FOperationBlock.protocol_version=1) And (FOperationBlock.protocol_available=0) then soob := 1
      else soob := 3;}
      soob := 3;
    end else begin
      {Old versions:
      if (FOperationBlock.protocol_version=1) And (FOperationBlock.protocol_available=0) then soob := 0
      else soob := 2;}
      soob := 2;
      if (SaveToStorage) then begin
        {Old versions:
        // Introduced on protocol v2: soob = 4 when saving to storage
        soob := 4;}
        // Introduced on protocol v3: soob = 5 when saving to storage
        soob := 5; // V3 will always save PreviousUpdatedBlocks
      end;
    end;
    Stream.Write(soob,1);
    if (soob>=2) then begin
      Stream.Write(FOperationBlock.protocol_version, Sizeof(FOperationBlock.protocol_version));
      Stream.Write(FOperationBlock.protocol_available, Sizeof(FOperationBlock.protocol_available));
    end;
    //
    Stream.Write(FOperationBlock.block, Sizeof(FOperationBlock.block));
    //
    TStreamOp.WriteAnsiString(Stream,TAccountComp.AccountKey2RawString(FOperationBlock.account_key));
    Stream.Write(FOperationBlock.reward, Sizeof(FOperationBlock.reward));
    Stream.Write(FOperationBlock.fee, Sizeof(FOperationBlock.fee));
    Stream.Write(FOperationBlock.timestamp, Sizeof(FOperationBlock.timestamp));
    Stream.Write(FOperationBlock.compact_target, Sizeof(FOperationBlock.compact_target));
    Stream.Write(FOperationBlock.nonce, Sizeof(FOperationBlock.nonce));
    TStreamOp.WriteAnsiString(Stream, FOperationBlock.block_payload);
    TStreamOp.WriteAnsiString(Stream, FOperationBlock.initial_safe_box_hash);
    TStreamOp.WriteAnsiString(Stream, FOperationBlock.operations_hash);
    TStreamOp.WriteAnsiString(Stream, FOperationBlock.proof_of_work);
    { Basic size calculation:
    protocols : 2 words = 4 bytes
    block : 4 bytes
    Account_key (VARIABLE LENGTH) at least 2 + 34 + 34 for secp256k1 key = 70 bytes
    reward, fee, timestamp, compact_target, nonce = 8+8+4+4+4 = 28 bytes
    payload (VARIABLE LENGTH) minimum 2 bytes... but usually 40 by average = 40 bytes
    sbh, operations_hash, pow ( 32 + 32 + 32 ) =  96 bytes
    Total, by average: 242 bytes
    }
    if (Not save_only_OperationBlock) then begin
      Result := FOperationsHashTree.SaveOperationsHashTreeToStream(Stream,SaveToStorage);
      If (Result) And (SaveToStorage) And (soob=5) then begin
        FPreviousUpdatedBlocks.SaveToStream(Stream);
      end;
    end else Result := true;
  finally
    Unlock;
  end;
end;

class function TPCOperationsComp.SaveOperationBlockToStream(const OperationBlock: TOperationBlock; Stream: TStream): Boolean;
Var soob : Byte;
begin
  soob := 3;
  Stream.Write(soob,1);
  Stream.Write(OperationBlock.protocol_version, Sizeof(OperationBlock.protocol_version));
  Stream.Write(OperationBlock.protocol_available, Sizeof(OperationBlock.protocol_available));
  //
  Stream.Write(OperationBlock.block, Sizeof(OperationBlock.block));
  //
  TStreamOp.WriteAnsiString(Stream,TAccountComp.AccountKey2RawString(OperationBlock.account_key));
  Stream.Write(OperationBlock.reward, Sizeof(OperationBlock.reward));
  Stream.Write(OperationBlock.fee, Sizeof(OperationBlock.fee));
  Stream.Write(OperationBlock.timestamp, Sizeof(OperationBlock.timestamp));
  Stream.Write(OperationBlock.compact_target, Sizeof(OperationBlock.compact_target));
  Stream.Write(OperationBlock.nonce, Sizeof(OperationBlock.nonce));
  TStreamOp.WriteAnsiString(Stream, OperationBlock.block_payload);
  TStreamOp.WriteAnsiString(Stream, OperationBlock.initial_safe_box_hash);
  TStreamOp.WriteAnsiString(Stream, OperationBlock.operations_hash);
  TStreamOp.WriteAnsiString(Stream, OperationBlock.proof_of_work);
  Result := true;
end;

function TPCOperationsComp.Update_And_RecalcPOW(newNOnce, newTimestamp: Cardinal; newBlockPayload: TRawBytes) : Boolean;
Var i : Integer;
  _changedPayload : Boolean;
begin
  Lock;
  Try
    If newBlockPayload<>FOperationBlock.block_payload then begin
      _changedPayload := TPascalCoinProtocol.IsValidMinerBlockPayload(newBlockPayload);
    end else _changedPayload:=False;
    If (_changedPayload) Or (newNOnce<>FOperationBlock.nonce) Or (newTimestamp<>FOperationBlock.timestamp) then begin
      If _changedPayload then FOperationBlock.block_payload:=newBlockPayload;
      FOperationBlock.nonce:=newNOnce;
      FOperationBlock.timestamp:=newTimestamp;
      CalcProofOfWork(_changedPayload,FOperationBlock.proof_of_work);
      Result := True;
    end else Result := False;
  finally
    Unlock;
  end;
end;

procedure TPCOperationsComp.SetAccountKey(const value: TAccountKey);
begin
  Lock;
  Try
    if TAccountComp.AccountKey2RawString(value)=TAccountComp.AccountKey2RawString(FOperationBlock.account_key) then exit;
    FOperationBlock.account_key := value;
    Calc_Digest_Parts;
  finally
    Unlock;
  end;
end;

{$IF DEFINED(CIRCULAR_REFERENCE_PROBLEM)}
procedure TPCOperationsComp.SetBank(const value: TPCBank);
begin
  if FBank = value then exit;
  if Assigned(FBank) then begin
     FreeAndNil(FSafeBoxTransaction);
  end;
  FBank := value;
  if Assigned(value) then begin
    value.FreeNotification(Self);
    FSafeBoxTransaction := TPCSafeBoxTransaction.Create(FBank.SafeBox);
  end;
  Clear(true);
end;
{$ENDIF}

procedure TPCOperationsComp.SetBlockPayload(const Value: TRawBytes);
begin
  Update_And_RecalcPOW(FOperationBlock.nonce,FOperationBlock.timestamp,Value);
end;

procedure TPCOperationsComp.OnOperationsHashTreeChanged(Sender: TObject);
begin
  FOperationBlock.operations_hash:=FOperationsHashTree.HashTree;
  Calc_Digest_Part3;
end;

procedure TPCOperationsComp.SetnOnce(const value: Cardinal);
begin
  Update_And_RecalcPOW(value,FOperationBlock.timestamp,FOperationBlock.block_payload);
end;

procedure TPCOperationsComp.Settimestamp(const value: Cardinal);
begin
  Update_And_RecalcPOW(FOperationBlock.nonce,value,FOperationBlock.block_payload);
end;

procedure TPCOperationsComp.UpdateTimestamp;
Var ts : Cardinal;
begin
  Lock;
  Try
    ts := UnivDateTimeToUnix(DateTime2UnivDateTime(now));

    {$IF DEFINED(CIRCULAR_REFERENCE_PROBLEM)}
    if Assigned(FBank) then begin
      If FBank.FLastOperationBlock.timestamp>ts then ts := FBank.FLastOperationBlock.timestamp;
    end;
    {$ENDIF}
    timestamp := ts;
  finally
    Unlock;
  end;
end;

function TPCOperationsComp.GetMinerRewardPseudoOperation : TOperationResume;
begin
   Result := CT_TOperationResume_NUL;
   Result.valid := true;
   Result.Block := FOperationBlock.block;
   Result.time := self.OperationBlock.timestamp;
   Result.AffectedAccount := FOperationBlock.block * CT_AccountsPerBlock;
   Result.Amount := self.OperationBlock.reward;
   Result.Fee := self.OperationBlock.fee;
   Result.Balance := Result.Amount+Result.Fee;
   Result.OperationTxt := 'Miner reward';
end;

function TPCOperationsComp.ValidateOperationBlock(var errors : AnsiString): Boolean;
Var i : Integer;
begin
  errors := '';
  Result := False;
  Lock;
  Try
    If Not Assigned(SafeBoxTransaction) then begin
      errors := 'ERROR DEV 20170523-1';
      exit;
    end;
    If Not Assigned(SafeBoxTransaction.FreezedSafeBox) then begin
      errors := 'ERROR DEV 20170523-2';
      exit;
    end;
    // Check OperationBlock info:
    If not SafeBoxTransaction.FreezedSafeBox.IsValidNewOperationsBlock(OperationBlock,True,errors) then exit;
    // Execute SafeBoxTransaction operations:
    SafeBoxTransaction.Rollback;
    FPreviousUpdatedBlocks.Clear;
    for i := 0 to Count - 1 do begin
      If Not Operation[i].DoOperation(FPreviousUpdatedBlocks, SafeBoxTransaction,errors) then begin
        errors := 'Error executing operation '+inttostr(i+1)+'/'+inttostr(Count)+': '+errors;
        exit;
      end;
    end;
    // Check OperationsHash value is valid
    // New Build 2.1.7 use safe BinStrComp
    if TBaseType.BinStrComp(FOperationsHashTree.HashTree,OperationBlock.operations_hash)<>0 then begin
      errors := 'Invalid Operations Hash '+TCrypto.ToHexaString(OperationBlock.operations_hash)+'<>'+TCrypto.ToHexaString(FOperationsHashTree.HashTree);
      exit;
    end;
    // Check OperationBlock with SafeBox info:
    if (SafeBoxTransaction.FreezedSafeBox.TotalBalance<>(SafeBoxTransaction.TotalBalance+SafeBoxTransaction.TotalFee)) then begin
      errors := Format('Invalid integrity balance at SafeBox. Actual Balance:%d  New Balance:(%d + fee %d = %d)',
        [SafeBoxTransaction.FreezedSafeBox.TotalBalance,
          SafeBoxTransaction.TotalBalance,
          SafeBoxTransaction.TotalFee,
          SafeBoxTransaction.TotalBalance+SafeBoxTransaction.TotalFee]);
      exit;
    end;
    // Check fee value
    if (SafeBoxTransaction.TotalFee<>OperationBlock.fee) then begin
      errors := Format('Invalid fee integrity at SafeBoxTransaction. New Balance:(%d + fee %d = %d)  OperationBlock.fee:%d',
        [
          SafeBoxTransaction.TotalBalance,
          SafeBoxTransaction.TotalFee,
          SafeBoxTransaction.TotalBalance+SafeBoxTransaction.TotalFee,
          OperationBlock.fee]);
      exit;
    end;

    Result := true;
  finally
    Unlock;
  end;
end;

procedure TPCOperationsComp.Lock;
begin
  FOperationsLock.Acquire;
end;

procedure TPCOperationsComp.Unlock;
begin
  FOperationsLock.Release;
end;

end.
