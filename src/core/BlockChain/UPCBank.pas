unit UPCBank;

interface

uses
  Classes, UStorage, UPCSafeBox, UPCOperationsComp, UOperationBlock, UPCBankLog, UThread, UStorageClass, UBlockAccount, ULog;

type
  { TPCBank }
  TPCBank = Class(TComponent)
  private
    FStorage : TStorage;
    FSafeBox: TPCSafeBox;
    FLastBlockCache : TPCOperationsComp;
    FLastOperationBlock: TOperationBlock;
    FIsRestoringFromFile: Boolean;
    FUpgradingToV2: Boolean;
    FOnLog: TPCBankLog;
    FBankLock: TPCCriticalSection;
    FNotifyList : TList;
    FStorageClass: TStorageClass;
    function GetStorage: TStorage;
    procedure SetStorageClass(const Value: TStorageClass);
  public
    Constructor Create(AOwner: TComponent); Override;
    Destructor Destroy; Override;
    Function BlocksCount: Cardinal;
    Function AccountsCount : Cardinal;
    procedure AssignTo(Dest: TPersistent); Override;
    function GetActualTargetSecondsAverage(BackBlocks : Cardinal): Real;
    function GetTargetSecondsAverage(FromBlock,BackBlocks : Cardinal): Real;
    function LoadBankFromStream(Stream : TStream; useSecureLoad : Boolean; var errors : AnsiString) : Boolean;
    Procedure Clear;
    Function LoadOperations(Operations : TPCOperationsComp; Block : Cardinal) : Boolean;
    Property SafeBox : TPCSafeBox read FSafeBox;
    Function AddNewBlockChainBlock(Operations: TPCOperationsComp; MaxAllowedTimestamp : Cardinal; var newBlock: TBlockAccount; var errors: AnsiString): Boolean;
    Procedure DiskRestoreFromOperations(max_block : Int64);
    Procedure UpdateValuesFromSafebox;
    Procedure NewLog(Operations: TPCOperationsComp; Logtype: TLogType; Logtxt: AnsiString);
    Property OnLog: TPCBankLog read FOnLog write FOnLog;
    Property LastOperationBlock : TOperationBlock read FLastOperationBlock; // TODO: Use
    Property Storage : TStorage read GetStorage;
    Property StorageClass : TStorageClass read FStorageClass write SetStorageClass;
    Function IsReady(Var CurrentProcess : AnsiString) : Boolean;
    Property LastBlockFound : TPCOperationsComp read FLastBlockCache;
    Property UpgradingToV2 : Boolean read FUpgradingToV2;

    // Skybuck: added property for NotifyList so TPCBankNotify can access it
    property NotifyList : TList read FNotifyList;
  End;

var
  PascalCoinBank : TPCBank;

implementation

uses
  SysUtils, UCrypto, UPCBankNotify, UConst;

{ TPCBank }

function TPCBank.AccountsCount: Cardinal;
begin
  Result := FSafeBox.AccountsCount;
end;

function TPCBank.AddNewBlockChainBlock(Operations: TPCOperationsComp; MaxAllowedTimestamp : Cardinal; var newBlock: TBlockAccount; var errors: AnsiString): Boolean;
Var
  buffer, pow: AnsiString;
  i : Integer;
begin
  TPCThread.ProtectEnterCriticalSection(Self,FBankLock);
  Try
    Result := False;
    errors := '';
    Operations.Lock; // New Protection
    Try
      If Not Operations.ValidateOperationBlock(errors) then begin
        exit;
      end;
      if (Operations.OperationBlock.block > 0) then begin
        if ((MaxAllowedTimestamp>0) And (Operations.OperationBlock.timestamp>MaxAllowedTimestamp)) then begin
          errors := 'Invalid timestamp (Future time: New timestamp '+Inttostr(Operations.OperationBlock.timestamp)+' > max allowed '+inttostr(MaxAllowedTimestamp)+')';
          exit;
        end;
      end;
      // Ok, include!
      // WINNER !!!
      // Congrats!

      if Not Operations.SafeBoxTransaction.Commit(Operations.OperationBlock,errors) then begin
        exit;
      end;

      newBlock := SafeBox.Block(SafeBox.BlocksCount-1);

      // Initialize values
      FLastOperationBlock := Operations.OperationBlock;
      // log it!
      NewLog(Operations, ltupdate,
        Format('New block height:%d nOnce:%d timestamp:%d Operations:%d Fee:%d SafeBoxBalance:%d=%d PoW:%s Operations previous Safe Box hash:%s Future old Safe Box hash for next block:%s',
          [ Operations.OperationBlock.block,Operations.OperationBlock.nonce,Operations.OperationBlock.timestamp,
            Operations.Count,
            Operations.OperationBlock.fee,
            SafeBox.TotalBalance,
            Operations.SafeBoxTransaction.TotalBalance,
            TCrypto.ToHexaString(Operations.OperationBlock.proof_of_work),
            TCrypto.ToHexaString(Operations.OperationBlock.initial_safe_box_hash),
            TCrypto.ToHexaString(SafeBox.SafeBoxHash)]));
      // Save Operations to disk
      if Not FIsRestoringFromFile then begin
        Storage.SaveBlockChainBlock(Operations);
      end;
      FLastBlockCache.CopyFrom(Operations);
      Operations.Clear(true);
      Result := true;
    Finally
      if Not Result then begin
        NewLog(Operations, lterror, 'Invalid new block '+inttostr(Operations.OperationBlock.block)+': ' + errors+ ' > '+TPCOperationsComp.OperationBlockToText(Operations.OperationBlock));
      end;
      Operations.Unlock;
    End;
  Finally
    FBankLock.Release;
  End;
  if Result then begin
    for i := 0 to FNotifyList.Count - 1 do begin
      TPCBankNotify(FNotifyList.Items[i]).NotifyNewBlock;
    end;
  end;
end;

procedure TPCBank.AssignTo(Dest: TPersistent);
var d : TPCBank;
begin
  if (Not (Dest is TPCBank)) then begin
    inherited;
    exit;
  end;
  if (Self=Dest) then exit;

  d := TPCBank(Dest);
  d.SafeBox.CopyFrom(SafeBox);
  d.FLastOperationBlock := FLastOperationBlock;
  d.FIsRestoringFromFile := FIsRestoringFromFile;
  d.FLastBlockCache.CopyFrom( FLastBlockCache );
end;

function TPCBank.BlocksCount: Cardinal;
begin
  Result := SafeBox.BlocksCount;
end;

procedure TPCBank.Clear;
begin
  SafeBox.Clear;
  FLastOperationBlock := TPCOperationsComp.GetFirstBlock;
  FLastOperationBlock.initial_safe_box_hash := TCrypto.DoSha256(CT_Genesis_Magic_String_For_Old_Block_Hash); // Genesis hash
  FLastBlockCache.Clear(true);
  NewLog(Nil, ltupdate, 'Clear Bank');
end;

constructor TPCBank.Create(AOwner: TComponent);
begin
  inherited;
  FStorage := Nil;
  FStorageClass := Nil;
  FBankLock := TPCCriticalSection.Create('TPCBank_BANKLOCK');
  FIsRestoringFromFile := False;
  FOnLog := Nil;
  FSafeBox := TPCSafeBox.Create;
  FNotifyList := TList.Create;
  FLastBlockCache := TPCOperationsComp.Create;
  FIsRestoringFromFile:=False;
  FUpgradingToV2:=False;
  Clear;
end;

destructor TPCBank.Destroy;
var step : String;
begin
  Try
    step := 'Deleting critical section';
    FreeAndNil(FBankLock);
    step := 'Clear';
    Clear;
    step := 'Destroying LastBlockCache';
    FreeAndNil(FLastBlockCache);
    step := 'Destroying SafeBox';
    FreeAndNil(FSafeBox);
    step := 'Destroying NotifyList';
    FreeAndNil(FNotifyList);
    step := 'Destroying Storage';
    FreeAndNil(FStorage);
    step := 'inherited';
    inherited;
  Except
    On E:Exception do begin
      TLog.NewLog(lterror,Classname,'Error destroying Bank step: '+step+' Errors ('+E.ClassName+'): ' +E.Message);
      Raise;
    end;
  End;
end;

procedure TPCBank.DiskRestoreFromOperations(max_block : Int64);
Var
  errors: AnsiString;
  newBlock: TBlockAccount;
  Operations: TPCOperationsComp;
  n : Int64;
begin
  if FIsRestoringFromFile then begin
    TLog.NewLog(lterror,Classname,'Is Restoring!!!');
    raise Exception.Create('Is restoring!');
  end;
  TPCThread.ProtectEnterCriticalSection(Self,FBankLock);
  try
    FUpgradingToV2 := NOT Storage.HasUpgradedToVersion2;
    FIsRestoringFromFile := true;
    try
      Clear;
      Storage.Initialize;
      If (max_block<Storage.LastBlock) then n := max_block
      else n := Storage.LastBlock;
      Storage.RestoreBank(n);
      // Restore last blockchain
      if (BlocksCount>0) And (SafeBox.CurrentProtocol=CT_PROTOCOL_1) then begin
        if Not Storage.LoadBlockChainBlock(FLastBlockCache,BlocksCount-1) then begin
          NewLog(nil,lterror,'Cannot find blockchain '+inttostr(BlocksCount-1)+' so cannot accept bank current block '+inttostr(BlocksCount));
          Clear;
        end else begin
          FLastOperationBlock := FLastBlockCache.OperationBlock;
        end;
      end;
      NewLog(Nil, ltinfo,'Start restoring from disk operations (Max '+inttostr(max_block)+') BlockCount: '+inttostr(BlocksCount)+' Orphan: ' +Storage.Orphan);

      Operations := TPCOperationsComp.Create;
      try
        while ((BlocksCount<=max_block)) do begin
          if Storage.BlockExists(BlocksCount) then begin
            if Storage.LoadBlockChainBlock(Operations,BlocksCount) then begin
              SetLength(errors,0);
              if Not AddNewBlockChainBlock(Operations,0,newBlock,errors) then begin
                NewLog(Operations, lterror,'Error restoring block: ' + Inttostr(BlocksCount)+ ' Errors: ' + errors);
                Storage.DeleteBlockChainBlocks(BlocksCount);
                break;
              end else begin
                // To prevent continuous saving...
                If (BlocksCount MOD (CT_BankToDiskEveryNBlocks*10))=0 then begin
                  Storage.SaveBank;
                end;
              end;
            end else break;
          end else break;
        end;
        if FUpgradingToV2 then Storage.CleanupVersion1Data;
      finally
        Operations.Free;
      end;
      NewLog(Nil, ltinfo,'End restoring from disk operations (Max '+inttostr(max_block)+') Orphan: ' + Storage.Orphan+' Restored '+Inttostr(BlocksCount)+' blocks');
    finally
      FIsRestoringFromFile := False;
      FUpgradingToV2 := false;
    end;
  finally
    FBankLock.Release;
  end;
end;

procedure TPCBank.UpdateValuesFromSafebox;
Var aux : AnsiString;
  i : Integer;
begin
  { Will update current Bank state based on Safbox state
    Used when commiting a Safebox or rolling back }
  Try
    TPCThread.ProtectEnterCriticalSection(Self,FBankLock);
    try
      FLastBlockCache.Clear(True);
      FLastOperationBlock := TPCOperationsComp.GetFirstBlock;
      FLastOperationBlock.initial_safe_box_hash := TCrypto.DoSha256(CT_Genesis_Magic_String_For_Old_Block_Hash); // Genesis hash
      If FSafeBox.BlocksCount>0 then begin
        Storage.Initialize;
        If Storage.LoadBlockChainBlock(FLastBlockCache,FSafeBox.BlocksCount-1) then begin
          FLastOperationBlock := FLastBlockCache.OperationBlock;
        end else begin
          aux := 'Cannot read last operations block '+IntToStr(FSafeBox.BlocksCount-1)+' from blockchain';
          TLog.NewLog(lterror,ClassName,aux);
          Raise Exception.Create(aux);
        end;
      end;
      TLog.NewLog(ltinfo,ClassName,Format('Updated Bank with Safebox values. Current block:%d ',[FLastOperationBlock.block]));
    finally
      FBankLock.Release;
    end;
  finally
    for i := 0 to FNotifyList.Count - 1 do begin
      TPCBankNotify(FNotifyList.Items[i]).NotifyNewBlock;
    end;
  end;
end;

function TPCBank.GetActualTargetSecondsAverage(BackBlocks: Cardinal): Real;
Var ts1, ts2: Int64;
begin
  if BlocksCount>BackBlocks then begin
    ts1 := SafeBox.Block(BlocksCount-1).blockchainInfo.timestamp;
    ts2 := SafeBox.Block(BlocksCount-BackBlocks-1).blockchainInfo.timestamp;
  end else if (BlocksCount>1) then begin
    ts1 := SafeBox.Block(BlocksCount-1).blockchainInfo.timestamp;
    ts2 := SafeBox.Block(0).blockchainInfo.timestamp;
    BackBlocks := BlocksCount-1;
  end else begin
    Result := 0;
    exit;
  end;
  Result := (ts1 - ts2) / BackBlocks;
end;

function TPCBank.GetTargetSecondsAverage(FromBlock, BackBlocks: Cardinal): Real;
Var ts1, ts2: Int64;
begin
  If FromBlock>=BlocksCount then begin
    Result := 0;
    exit;
  end;
  if FromBlock>BackBlocks then begin
    ts1 := SafeBox.Block(FromBlock-1).blockchainInfo.timestamp;
    ts2 := SafeBox.Block(FromBlock-BackBlocks-1).blockchainInfo.timestamp;
  end else if (FromBlock>1) then begin
    ts1 := SafeBox.Block(FromBlock-1).blockchainInfo.timestamp;
    ts2 := SafeBox.Block(0).blockchainInfo.timestamp;
    BackBlocks := FromBlock-1;
  end else begin
    Result := 0;
    exit;
  end;
  Result := (ts1 - ts2) / BackBlocks;
end;

function TPCBank.GetStorage: TStorage;
begin
  if Not Assigned(FStorage) then begin
    if Not Assigned(FStorageClass) then raise Exception.Create('StorageClass not defined');
    FStorage := FStorageClass.Create(Self);
  end;
  Result := FStorage;
end;

function TPCBank.IsReady(Var CurrentProcess: AnsiString): Boolean;
begin
  Result := false;
  CurrentProcess := '';
  if FIsRestoringFromFile then begin
    if FUpgradingToV2 then
      CurrentProcess := 'Migrating to version 2 format'
    else
      CurrentProcess := 'Restoring from file'
  end else Result := true;
end;

function TPCBank.LoadBankFromStream(Stream: TStream; useSecureLoad : Boolean; var errors: AnsiString): Boolean;
Var LastReadBlock : TBlockAccount;
  i : Integer;
  auxSB : TPCSafeBox;
begin
  auxSB := Nil;
  Try
    If useSecureLoad then begin
      // When on secure load will load Stream in a separate SafeBox, changing only real SafeBox if successfully
      auxSB := TPCSafeBox.Create;
      Result := auxSB.LoadSafeBoxFromStream(Stream,true,LastReadBlock,errors);
      If Not Result then Exit;
    end;
    TPCThread.ProtectEnterCriticalSection(Self,FBankLock);
    try
      If Assigned(auxSB) then begin
        SafeBox.CopyFrom(auxSB);
      end else begin
        Result := SafeBox.LoadSafeBoxFromStream(Stream,false,LastReadBlock,errors);
      end;
      If Not Result then exit;
      If SafeBox.BlocksCount>0 then FLastOperationBlock := SafeBox.Block(SafeBox.BlocksCount-1).blockchainInfo
      else begin
        FLastOperationBlock := TPCOperationsComp.GetFirstBlock;
        FLastOperationBlock.initial_safe_box_hash := TCrypto.DoSha256(CT_Genesis_Magic_String_For_Old_Block_Hash); // Genesis hash
      end;
    finally
      FBankLock.Release;
    end;
    for i := 0 to FNotifyList.Count - 1 do begin
      TPCBankNotify(FNotifyList.Items[i]).NotifyNewBlock;
    end;
  finally
    If Assigned(auxSB) then auxSB.Free;
  end;
end;

function TPCBank.LoadOperations(Operations: TPCOperationsComp; Block: Cardinal): Boolean;
begin
  TPCThread.ProtectEnterCriticalSection(Self,FBankLock);
  try
    if (Block>0) AND (Block=FLastBlockCache.OperationBlock.block) then begin
      // Same as cache, sending cache
      Operations.CopyFrom(FLastBlockCache);
      Result := true;
    end else begin
      Result := Storage.LoadBlockChainBlock(Operations,Block);
    end;
  finally
    FBankLock.Release;
  end;
end;

procedure TPCBank.NewLog(Operations: TPCOperationsComp; Logtype: TLogType; Logtxt: AnsiString);
var s : AnsiString;
begin
  if Assigned(Operations) then s := Operations.ClassName
  else s := Classname;
  TLog.NewLog(Logtype,s,Logtxt);
  if Assigned(FOnLog) then
    FOnLog(Self, Operations, Logtype, Logtxt);
end;

procedure TPCBank.SetStorageClass(const Value: TStorageClass);
begin
  if FStorageClass=Value then exit;
  FStorageClass := Value;
  if Assigned(FStorage) then FreeAndNil(FStorage);
end;

end.
