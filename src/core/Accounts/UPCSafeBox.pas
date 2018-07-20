unit UPCSafeBox;

interface

uses
  Classes, UOrderedBlockAccountList, URawBytes, UOrderedRawList, UThread, UAccountKey, UBlockAccount, UAccountInfo, UAccountUpdateStyle, UOperationBlock, UPCSafeBoxHeader, UAccount;

type
  TPCSafeBox = Class
  private
    FBlockAccountsList : TList; // Used when has no PreviousSafebox
    FModifiedBlocksSeparatedChain : TOrderedBlockAccountList; // Used when has PreviousSafebox (Used if we are on a Separated chain)
    //
    FListOfOrderedAccountKeysList : TList;
    FBufferBlocksHash: TRawBytes;
    FOrderedByName : TOrderedRawList;
    FTotalBalance: Int64;
    FSafeBoxHash : TRawBytes;
    FLock: TPCCriticalSection; // Thread safe
    FWorkSum : UInt64;
    FCurrentProtocol: Integer;
    // Snapshots utility new on V3
    FSnapshots : TList; // Will save a Snapshots lists in order to rollback Safebox to a previous block state
    FMaxSafeboxSnapshots : Integer;
    // To be added to next snapshot
    FModifiedBlocksPreviousState : TOrderedBlockAccountList;
    FModifiedBlocksFinalState : TOrderedBlockAccountList;
    FAddedNamesSincePreviousSafebox : TOrderedRawList;
    FDeletedNamesSincePreviousSafebox : TOrderedRawList;
    // Is capturing data from a snapshot?
    FPreviousSafeBox : TPCSafeBox;  // PreviousSafebox is the Safebox with snpashots where this safebox searches
    FPreviousSafeboxOriginBlock : Integer;
    // Has chains based on this Safebox?
    FSubChains : TList; // Will link to subchains (other safebox) based on a current snapshot of this safebox
    //
    Procedure AccountKeyListAddAccounts(Const AccountKey : TAccountKey; const accounts : Array of Cardinal);
    Procedure AccountKeyListRemoveAccount(Const AccountKey : TAccountKey; const accounts : Array of Cardinal);
    // V3
    procedure SearchBlockWhenOnSeparatedChain(blockNumber : Cardinal; out blockAccount : TBlockAccount);
  protected
    FTotalFee: Int64;
  public
    Constructor Create;
    Destructor Destroy; override;
    procedure SetToPrevious(APreviousSafeBox : TPCSafeBox; StartBlock : Cardinal);
    procedure CommitToPrevious;
    procedure RollBackToSnapshot(snapshotBlock : Cardinal);
    function AccountsCount: Integer;
    Function BlocksCount : Integer;
    Procedure CopyFrom(accounts : TPCSafeBox);
    Class Function CalcBlockHash(const block : TBlockAccount; useProtocol2Method : Boolean):TRawBytes;
    Class Function BlockAccountToText(Const block : TBlockAccount):AnsiString;
    Function LoadSafeBoxFromStream(Stream : TStream; checkAll : Boolean; var LastReadBlock : TBlockAccount; var errors : AnsiString) : Boolean;
    Class Function LoadSafeBoxStreamHeader(Stream : TStream; var sbHeader : TPCSafeBoxHeader) : Boolean;
    Class Function SaveSafeBoxStreamHeader(Stream : TStream; protocol : Word; OffsetStartBlock, OffsetEndBlock, CurrentSafeBoxBlocksCount : Cardinal) : Boolean;
    Class Function MustSafeBoxBeSaved(BlocksCount : Cardinal) : Boolean;
    Procedure SaveSafeBoxBlockToAStream(Stream : TStream; nBlock : Cardinal);
    Procedure SaveSafeBoxToAStream(Stream : TStream; FromBlock, ToBlock : Cardinal);
    class Function CopySafeBoxStream(Source,Dest : TStream; FromBlock, ToBlock : Cardinal; var errors : AnsiString) : Boolean;
    class Function ConcatSafeBoxStream(Source1, Source2, Dest : TStream; var errors : AnsiString) : Boolean;
    class function ValidAccountName(const new_name : TRawBytes; var errors : AnsiString) : Boolean;

    Function IsValidNewOperationsBlock(Const newOperationBlock : TOperationBlock; checkSafeBoxHash : Boolean; var errors : AnsiString) : Boolean;
    class Function IsValidOperationBlock(Const newOperationBlock : TOperationBlock; var errors : AnsiString) : Boolean;
    Function GetActualTargetHash(protocolVersion : Word): TRawBytes;
    Function GetActualCompactTargetHash(protocolVersion : Word): Cardinal;
    Function FindAccountByName(aName : AnsiString) : Integer;

    Procedure Clear;
    Function Account(account_number : Cardinal) : TAccount;
    Function Block(block_number : Cardinal) : TBlockAccount;
    Function CalcSafeBoxHash : TRawBytes;
    Function CalcBlockHashRateInKhs(block_number : Cardinal; Previous_blocks_average : Cardinal) : Int64;
    Property TotalBalance : Int64 read FTotalBalance;

    // Skybuck: property added for TotalFee to make it accessable to TPCSafeBoxTransaction
    Property TotalFee : int64 read FTotalFee;
    Procedure StartThreadSafe;
    Procedure EndThreadSave;
    Property SafeBoxHash : TRawBytes read FSafeBoxHash;
    Property WorkSum : UInt64 read FWorkSum;
    Property CurrentProtocol : Integer read FCurrentProtocol;
    function CanUpgradeToProtocol(newProtocolVersion : Word) : Boolean;
    procedure CheckMemory;
    Property PreviousSafeboxOriginBlock : Integer Read FPreviousSafeboxOriginBlock;
    Function GetMinimumAvailableSnapshotBlock : Integer;
    Function HasSnapshotForBlock(block_number : Cardinal) : Boolean;

    // Skybuck: moved to here to make it accessable to TPCSafeBoxTransaction
    Procedure UpdateAccount(account_number : Cardinal; const newAccountInfo: TAccountInfo; const newName : TRawBytes; newType : Word; newBalance: UInt64; newN_operation: Cardinal;
      accountUpdateStyle : TAccountUpdateStyle; newUpdated_block, newPrevious_Updated_block : Cardinal);
    Function AddNew(Const blockChain : TOperationBlock) : TBlockAccount;
    function DoUpgradeToProtocol2 : Boolean;
    function DoUpgradeToProtocol3 : Boolean;

    // Skybuck: added this to make UOrderedAccountKeysList.pas work.
    property ListOfOrderedAccountKeysList : TList read FListOfOrderedAccountKeysList;
  End;

function Check_Safebox_Names_Consistency(sb : TPCSafeBox; const title :String; var errors : AnsiString) : Boolean;
Procedure Check_Safebox_Integrity(sb : TPCSafebox; title: String);

implementation

uses
  UConst, SysUtils, UMemAccount, UPBlockAccount, UTickCount, UPlatform, ULog, UAccountComp, UBaseType, UPascalCoinProtocol,
  UAccountState, UMemBlockAccount, UOrderedAccountKeysList, UCrypto, UBigNum, UStreamOp, UCardinalsArray, UAccountKeyStorage;

{$include MemoryReductionSettings.inc}

{ This function is for testing purpose only.
  Will check if Account Names are well assigned and stored }
function Check_Safebox_Names_Consistency(sb : TPCSafeBox; const title :String; var errors : AnsiString) : Boolean;
Var i,j : Integer;
  acc : TAccount;
  auxs : TRawBytes;
  tc : TTickCount;
Begin
  tc := TPlatform.GetTickCount;
  Try
    errors := '';
    Result := True;
    for i:=0 to sb.AccountsCount-1 do begin
      acc := sb.Account(i);
      If acc.name<>'' then begin
        j := sb.FindAccountByName(acc.name);
        If j<>i then begin
          errors :=errors + Format(' > Account %d name:%s found at:%d<>Theorical:%d',[acc.account,acc.name,j,i]);
        end;
      end;
    end;
    // Reverse
    for i:=0 to sb.FOrderedByName.Count-1 do begin
      j := sb.FOrderedByName.GetTag(i);
      auxs := sb.FOrderedByName.Get(i);
      acc := sb.Account(j);
      If (auxs<>acc.name) then begin
        errors :=errors + Format(' > Name:%s at thorical account %d not valid (found %s)',[auxs,j,acc.name]);
      end;
    end;
    If (errors<>'') then begin
      errors := title+' '+errors;
      Result := False;
      TLog.NewLog(lterror,'Check_Safebox_Names_Consistency',errors);
    end;
  finally
    TLog.NewLog(ltDebug,'Check_Safebox_Names_Consistency','Used time '+IntToStr(TPlatform.GetElapsedMilliseconds(tc))+' milliseconds');
  end;
end;

{ This function is for testing purpose only.
  Will check if Accounts are Ok }
Procedure Check_Safebox_Integrity(sb : TPCSafebox; title: String);
var i,j,maxBlock : Integer;
  bl_my, bl_modified : TBlockAccount;
  auxH : TRawBytes;
Begin
  For i:=0 to sb.FModifiedBlocksFinalState.Count-1 do begin
    bl_modified := sb.FModifiedBlocksFinalState.Get(i);
    bl_my := sb.Block(bl_modified.blockchainInfo.block);
    If Not TAccountComp.EqualBlockAccounts(bl_my,bl_modified) then begin
      Raise Exception.Create(Format('%s Integrity on modified (i)=%d for block number:%d',[title, i,bl_my.blockchainInfo.block]));
    end;
    If TBaseType.BinStrComp( sb.CalcBlockHash(bl_modified,sb.FCurrentProtocol>=CT_PROTOCOL_2), bl_modified.block_hash)<>0 then begin
      Raise Exception.Create(Format('%s Integrity on block hash (i)=%d for block number:%d',[title, i,bl_my.blockchainInfo.block]));
    end;
  end;
  auxH := '';
  maxBlock := sb.BlocksCount;
  for i:=0 to sb.BlocksCount-1 do begin
    bl_my := sb.Block(i);
    for j:=Low(bl_my.accounts) to High(bl_my.accounts) do begin
      If maxBlock < (bl_my.accounts[j].updated_block) then begin
        Raise Exception.Create(Format('%s Integrity on (i)=%d for block account:%d updated on %d > maxBlock %d',[title, i,bl_my.accounts[j].account,bl_my.accounts[j].updated_block,maxBlock]));
      end;
    end;
    auxH := auxH + bl_my.block_hash;
  end;
  If TBaseType.BinStrComp(sb.FBufferBlocksHash,auxH)<>0 then begin
    Raise Exception.Create(Format('%s Integrity different Buffer Block Hash',[title]));
  end;
end;


{ TPCSafeBox }
Type
  TSafeboxSnapshot = Record
    nBlockNumber : Cardinal;
    oldBlocks : TOrderedBlockAccountList; // Saves old blocks values on modified blocks
    newBlocks : TOrderedBlockAccountList; // Saves final blocks values on modified blocks
    namesDeleted : TOrderedRawList;
    namesAdded : TOrderedRawList;
    oldBufferBlocksHash: TRawBytes;
    oldTotalBalance: Int64;
    oldTotalFee: Int64;
    oldSafeBoxHash : TRawBytes;
    oldWorkSum : UInt64;
    oldCurrentProtocol: Integer;
  end;
  PSafeboxSnapshot = ^TSafeboxSnapshot;

Const
  CT_TSafeboxSnapshot_NUL : TSafeboxSnapshot = (nBlockNumber : 0; oldBlocks : Nil; newBlocks : Nil; namesDeleted : Nil; namesAdded : Nil;oldBufferBlocksHash:'';oldTotalBalance:0;oldTotalFee:0;oldSafeBoxHash:'';oldWorkSum:0;oldCurrentProtocol:0);

function TPCSafeBox.Account(account_number: Cardinal): TAccount;
var
  iBlock : Integer;
  blockAccount : TBlockAccount;
begin
  StartThreadSafe;
  try
    iBlock:=(Integer(account_number)  DIV CT_AccountsPerBlock);
    If (Assigned(FPreviousSafeBox)) then begin
      SearchBlockWhenOnSeparatedChain(iBlock,blockAccount);
      Result := blockAccount.accounts[account_number MOD CT_AccountsPerBlock];
    end else begin
      if (iBlock<0) Or (iBlock>=FBlockAccountsList.Count) then raise Exception.Create('Invalid account: '+IntToStr(account_number));
      ToTAccount(PBlockAccount(FBlockAccountsList.Items[iBlock])^.accounts[account_number MOD CT_AccountsPerBlock],account_number,Result);
    end;
  finally
    EndThreadSave;
  end;
end;

function TPCSafeBox.AddNew(const blockChain: TOperationBlock): TBlockAccount;
{ PIP-0011 (dev reward) workflow: (** Only on V3 protocol **)
  - Account 0 is Master Account
  - Account 0 type field (2 bytes: 0..65535) will store a Value, this value is the "dev account"
  - The "dev account" can be any account between 0..65535, and can be changed at any time.
  - The 80% of the blockChain.reward + miner fees will be added on first mined account (like V1 and V2)
  - The miner will also receive ownership of first four accounts (Before, all accounts where for miner)
  - The "dev account" will receive the last created account ownership and the 20% of the blockChain.reward
  - Example:
    - Account(0).type = 12345    <-- dev account = 12345
    - blockChain.block = 234567  <-- New block height. Accounts generated from 1172835..1172839
    - blockChain.reward = 50 PASC
    - blockChain.fee = 0.9876 PASC
    - blockChain.account_key = Miner public key
    - New generated accounts:
      - [0] = 1172835 balance: 40.9876 owner: Miner
      - [1] = 1172836 balance: 0       owner: Miner
      - [2] = 1172837 balance: 0       owner: Miner
      - [3] = 1172838 balance: 0       owner: Miner
      - [4] = 1172839 balance: 10.0000 owner: Account 12345 owner, same owner than "dev account"
    - Safebox balance increase: 50 PASC
  }

var i, base_addr : Integer;
  Pblock : PBlockAccount;
  accs_miner, accs_dev : Array of cardinal;
  Psnapshot : PSafeboxSnapshot;
  //
  account_dev,
  account_0 : TAccount;
  //
  acc_0_miner_reward,acc_4_dev_reward : Int64;
  acc_4_for_dev : Boolean;
begin
  Result := CT_BlockAccount_NUL;
  Result.blockchainInfo := blockChain;
  If blockChain.block<>BlocksCount then Raise Exception.Create(Format('ERROR DEV 20170427-2 blockchain.block:%d <> BlocksCount:%d',[blockChain.block,BlocksCount]));

  // wow wrong calcultions detected WTF ! let's exploit the fuck out of this ! ;) :)
  // let's first verify that these bugs exist in original distribution from the internet ! ;)
  If blockChain.fee<>FTotalFee then Raise Exception.Create(Format('ERROR DEV 20170427-3 blockchain.fee:%d <> Safebox.TotalFee:%d',[blockChain.fee,FTotalFee]));

  TPascalCoinProtocol.GetRewardDistributionForNewBlock(blockChain,acc_0_miner_reward,acc_4_dev_reward,acc_4_for_dev);
  account_dev := CT_Account_NUL;
  If (acc_4_for_dev) then begin
    account_0 := Account(0); // Account 0 is master account, will store "dev account" in type field
    If (AccountsCount>account_0.account_type) then begin
      account_dev := Account(account_0.account_type);
    end else account_dev := account_0;
  end;

  base_addr := BlocksCount * CT_AccountsPerBlock;
  setlength(accs_miner,0);
  setlength(accs_dev,0);
  for i := Low(Result.accounts) to High(Result.accounts) do begin
    Result.accounts[i] := CT_Account_NUL;
    Result.accounts[i].account := base_addr + i;
    Result.accounts[i].accountInfo.state := as_Normal;
    Result.accounts[i].updated_block := BlocksCount;
    Result.accounts[i].n_operation := 0;
    if (acc_4_for_dev) And (i=CT_AccountsPerBlock-1) then begin
      Result.accounts[i].accountInfo.accountKey := account_dev.accountInfo.accountKey;
      SetLength(accs_dev,length(accs_dev)+1);
      accs_dev[High(accs_dev)] := base_addr + i;
      Result.accounts[i].balance := acc_4_dev_reward;
    end else begin
      Result.accounts[i].accountInfo.accountKey := blockChain.account_key;
      SetLength(accs_miner,length(accs_miner)+1);
      accs_miner[High(accs_miner)] := base_addr + i;
      if i=Low(Result.accounts) then begin
        // Only first account wins the reward + fee
        Result.accounts[i].balance := acc_0_miner_reward;
      end else begin
      end;
    end;
  end;
  FWorkSum := FWorkSum + Result.blockchainInfo.compact_target;
  Result.AccumulatedWork := FWorkSum;
  // Calc block hash
  Result.block_hash := CalcBlockHash(Result,FCurrentProtocol >= CT_PROTOCOL_2);
  If Assigned(FPreviousSafeBox) then begin
    FModifiedBlocksSeparatedChain.Add(Result);
  end else begin
    New(Pblock);
    ToTMemBlockAccount(Result,Pblock^);
    FBlockAccountsList.Add(Pblock);
  end;
  FBufferBlocksHash := FBufferBlocksHash+Result.block_hash;
  FTotalBalance := FTotalBalance + (blockChain.reward + blockChain.fee);
  FTotalFee := FTotalFee - blockChain.fee;
  If (length(accs_miner)>0) then begin
    AccountKeyListAddAccounts(blockChain.account_key,accs_miner);
  end;
  If (length(accs_dev)>0) then begin
    AccountKeyListAddAccounts(account_dev.accountInfo.accountKey,accs_dev);
  end;
  // Calculating new value of safebox
  FSafeBoxHash := CalcSafeBoxHash;

  // Save previous snapshot with current state
  If (FMaxSafeboxSnapshots>0) then begin
    new(Psnapshot);
    Psnapshot^:=CT_TSafeboxSnapshot_NUL;
    Psnapshot^.nBlockNumber:=blockChain.block;
    Psnapshot^.oldBlocks := FModifiedBlocksPreviousState;
    Psnapshot^.newBlocks := FModifiedBlocksFinalState;
    Psnapshot^.namesDeleted := FDeletedNamesSincePreviousSafebox;
    Psnapshot^.namesAdded := FAddedNamesSincePreviousSafebox;
    Psnapshot^.oldBufferBlocksHash:=FBufferBlocksHash;
    Psnapshot^.oldTotalBalance:=FTotalBalance;
    Psnapshot^.oldTotalFee:=FTotalFee;
    Psnapshot^.oldSafeBoxHash := FSafeBoxHash;
    Psnapshot^.oldWorkSum := FWorkSum;
    Psnapshot^.oldCurrentProtocol:= FCurrentProtocol;
    FSnapshots.Add(Psnapshot);
    FModifiedBlocksPreviousState := TOrderedBlockAccountList.Create;
    FModifiedBlocksFinalState := TOrderedBlockAccountList.Create;
    FAddedNamesSincePreviousSafebox := TOrderedRawList.Create;
    FDeletedNamesSincePreviousSafebox := TOrderedRawList.Create;
    // Remove old snapshots!
    If (FSubChains.Count=0) And (Not Assigned(FPreviousSafeBox)) then begin
      // Remove ONLY if there is no subchain based on my snapshots!
      While (FSnapshots.Count>FMaxSafeboxSnapshots) do begin
        Psnapshot := FSnapshots[0];
        TLog.NewLog(ltdebug,Classname,Format('Deleting snapshot for block %d',[Psnapshot^.nBlockNumber]));
        FSnapshots.Delete(0);
        FreeAndNil( Psnapshot.oldBlocks );
        FreeAndNil( Psnapshot.newBlocks );
        FreeAndNil( Psnapshot.namesAdded );
        FreeAndNil( Psnapshot.namesDeleted );
        Psnapshot^.oldBufferBlocksHash:='';
        Psnapshot^.oldSafeBoxHash:='';
        Dispose(Psnapshot);
      end;
    end;
  end else begin
    FModifiedBlocksPreviousState.Clear;
    FModifiedBlocksFinalState.Clear;
    FAddedNamesSincePreviousSafebox.Clear;
    FDeletedNamesSincePreviousSafebox.Clear;
  end;
end;

procedure TPCSafeBox.AccountKeyListAddAccounts(const AccountKey: TAccountKey; const accounts: array of Cardinal);
Var i : Integer;
begin
  for i := 0 to FListOfOrderedAccountKeysList.count-1 do begin
    TOrderedAccountKeysList( FListOfOrderedAccountKeysList[i] ).AddAccounts(AccountKey,accounts);
  end;
end;

procedure TPCSafeBox.AccountKeyListRemoveAccount(const AccountKey: TAccountKey; const accounts: array of Cardinal);
Var i : Integer;
begin
  for i := 0 to FListOfOrderedAccountKeysList.count-1 do begin
    TOrderedAccountKeysList( FListOfOrderedAccountKeysList[i] ).RemoveAccounts(AccountKey,accounts);
  end;
end;

function TPCSafeBox.AccountsCount: Integer;
begin
  StartThreadSafe;
  try
    Result := BlocksCount * CT_AccountsPerBlock;
  finally
    EndThreadSave;
  end;
end;

function TPCSafeBox.Block(block_number: Cardinal): TBlockAccount;
begin
  StartThreadSafe;
  try
    If (Assigned(FPreviousSafeBox)) then begin
      if (block_number<0) Or (block_number>=BlocksCount) then raise Exception.Create('Invalid block number for chain: '+inttostr(block_number)+' max: '+IntToStr(BlocksCount-1));
      SearchBlockWhenOnSeparatedChain(block_number,Result);
    end else begin
      if (block_number<0) Or (block_number>=FBlockAccountsList.Count) then raise Exception.Create('Invalid block number: '+inttostr(block_number)+' max: '+IntToStr(FBlockAccountsList.Count-1));
      ToTBlockAccount(PBlockAccount(FBlockAccountsList.Items[block_number])^,block_number,Result);
    end;
  finally
    EndThreadSave;
  end;
end;

class function TPCSafeBox.BlockAccountToText(const block: TBlockAccount): AnsiString;
begin
  Result := Format('Block:%d Timestamp:%d BlockHash:%s',
    [block.blockchainInfo.block, block.blockchainInfo.timestamp,
       TCrypto.ToHexaString(block.block_hash)]);
end;

function TPCSafeBox.BlocksCount: Integer;
begin
  StartThreadSafe;
  try
    If Assigned(FPreviousSafeBox) then begin
      Result := FModifiedBlocksSeparatedChain.MaxBlockNumber+1;
      If (Result<=FPreviousSafeboxOriginBlock) then begin
        Result := FPreviousSafeboxOriginBlock+1;
      end;
    end else begin
      Result := FBlockAccountsList.Count;
    end;
  finally
    EndThreadSave;
  end;
end;

class function TPCSafeBox.CalcBlockHash(const block : TBlockAccount; useProtocol2Method : Boolean): TRawBytes;
  // Protocol v2 update:
  // In order to store values to generate PoW and allow Safebox checkpointing, we
  // store info about TOperationBlock on each row and use it to obtain blockchash
Var raw: TRawBytes;
  ms : TMemoryStream;
  i : Integer;
begin
  ms := TMemoryStream.Create;
  try
    If (Not useProtocol2Method) then begin
      // PROTOCOL 1 BlockHash calculation
      ms.Write(block.blockchainInfo.block,4); // Little endian
      for i := Low(block.accounts) to High(block.accounts) do begin
        ms.Write(block.accounts[i].account,4);  // Little endian
        raw := TAccountComp.AccountInfo2RawString(block.accounts[i].accountInfo);
        ms.WriteBuffer(raw[1],length(raw)); // Raw bytes
        ms.Write(block.accounts[i].balance,SizeOf(Uint64));  // Little endian
        ms.Write(block.accounts[i].updated_block,4);  // Little endian
        ms.Write(block.accounts[i].n_operation,4); // Little endian
      end;
      ms.Write(block.blockchainInfo.timestamp,4); // Little endian
    end else begin
      // PROTOCOL 2 BlockHash calculation
      TAccountComp.SaveTOperationBlockToStream(ms,block.blockchainInfo);
      for i := Low(block.accounts) to High(block.accounts) do begin
        ms.Write(block.accounts[i].account,4);  // Little endian
        raw := TAccountComp.AccountInfo2RawString(block.accounts[i].accountInfo);
        ms.WriteBuffer(raw[1],length(raw)); // Raw bytes
        ms.Write(block.accounts[i].balance,SizeOf(Uint64));  // Little endian
        ms.Write(block.accounts[i].updated_block,4);  // Little endian
        ms.Write(block.accounts[i].n_operation,4); // Little endian
        // Use new Protocol 2 fields
        If length(block.accounts[i].name)>0 then begin
          ms.WriteBuffer(block.accounts[i].name[1],length(block.accounts[i].name));
        end;
        ms.Write(block.accounts[i].account_type,2);
      end;
      ms.Write(block.AccumulatedWork,SizeOf(block.AccumulatedWork));
    end;
    Result := TCrypto.DoSha256(ms.Memory,ms.Size)
  finally
    ms.Free;
  end;
end;

function TPCSafeBox.CalcBlockHashRateInKhs(block_number: Cardinal;
  Previous_blocks_average: Cardinal): Int64;
Var c,t : Cardinal;
  t_sum : Extended;
  bn, bn_sum : TBigNum;
begin
  FLock.Acquire;
  Try
    bn_sum := TBigNum.Create;
    try
      if (block_number=0) then begin
        Result := 1;
        exit;
      end;
      if (block_number<0) Or (block_number>=FBlockAccountsList.Count) then raise Exception.Create('Invalid block number: '+inttostr(block_number));
      if (Previous_blocks_average<=0) then raise Exception.Create('Dev error 20161016-1');
      if (Previous_blocks_average>block_number) then Previous_blocks_average := block_number;
      //
      c := (block_number - Previous_blocks_average)+1;
      t_sum := 0;
      while (c<=block_number) do begin
        bn := TBigNum.TargetToHashRate(PBlockAccount(FBlockAccountsList.Items[c])^.blockchainInfo.compact_target);
        try
          bn_sum.Add(bn);
        finally
          bn.Free;
        end;
        t_sum := t_sum + (PBlockAccount(FBlockAccountsList.Items[c])^.blockchainInfo.timestamp - PBlockAccount(FBlockAccountsList.Items[c-1])^.blockchainInfo.timestamp);
        inc(c);
      end;
      bn_sum.Divide(Previous_blocks_average); // Obtain target average
      t_sum := t_sum / Previous_blocks_average; // time average
      t := Round(t_sum);
      if (t<>0) then begin
        bn_sum.Divide(t);
      end;
      Result := bn_sum.Divide(1024).Value; // Value in Kh/s
    Finally
      bn_sum.Free;
    end;
  Finally
    FLock.Release;
  End;
end;

function TPCSafeBox.CalcSafeBoxHash: TRawBytes;
begin
  StartThreadSafe;
  try
    // If No buffer to hash is because it's firts block... so use Genesis: CT_Genesis_Magic_String_For_Old_Block_Hash
    if (FBufferBlocksHash='') then Result := TCrypto.DoSha256(CT_Genesis_Magic_String_For_Old_Block_Hash)
    else Result := TCrypto.DoSha256(FBufferBlocksHash);
  finally
    EndThreadSave;
  end;
end;

function TPCSafeBox.CanUpgradeToProtocol(newProtocolVersion : Word) : Boolean;
begin
  If (newProtocolVersion=CT_PROTOCOL_2) then begin
    Result := (FCurrentProtocol<CT_PROTOCOL_2) and (BlocksCount >= CT_Protocol_Upgrade_v2_MinBlock);
  end else if (newProtocolVersion=CT_PROTOCOL_3) then begin
    Result := (FCurrentProtocol=CT_PROTOCOL_2) And (BlocksCount >= CT_Protocol_Upgrade_v3_MinBlock);
  end else Result := False;
end;

procedure TPCSafeBox.CheckMemory;
  { Note about Free Pascal compiler
    When compiling using Delphi it's memory manager more is efficient and does not increase, but
    When compiling using Free Pascal Compiler, is a good solution to "force" generate a new SafeBox
    in order to free memory not used. Tested with FPC 3.0 }
{$IFDEF FPC}
Var sb : TPCSafeBox;
  tc : TTickCount;
  auxSnapshotsList : TList;
  i : Integer;
{$ENDIF}
begin
  {$IFDEF FPC}
  StartThreadSafe;
  try
    If Assigned(FPreviousSafeBox) then Exit; // When loading from snapshot, does not allow to check memory!
    tc := TPlatform.GetTickCount;
    sb := TPCSafeBox.Create;
    try
      //
      auxSnapshotsList := TList.Create;
      Try
        // Save snapshots:
        auxSnapshotsList.Assign(FSnapshots);
        FSnapshots.Clear;
        //
        sb.CopyFrom(Self);
        Self.Clear;
        Self.CopyFrom(sb);
        // Restore snapshots:
        FSnapshots.Assign(auxSnapshotsList);
        // Clear changes to do not fire key activity
        for i := 0 to FListOfOrderedAccountKeysList.count-1 do begin
          TOrderedAccountKeysList( FListOfOrderedAccountKeysList[i] ).ClearAccountKeyChanges;
        end;
      finally
        auxSnapshotsList.Free;
      end;
    finally
      sb.Free;
    end;
    TLog.NewLog(ltDebug,Classname,'Checked memory '+IntToStr(TPlatform.GetElapsedMilliseconds(tc))+' milliseconds');
  finally
    EndThreadSave;
  end;
  {$ENDIF}
end;

function TPCSafeBox.GetMinimumAvailableSnapshotBlock: Integer;
Var Pss : PSafeboxSnapshot;
begin
  Result := -1;
  StartThreadSafe;
  Try
    If (FSnapshots.Count>0) then begin
      Pss := FSnapshots[0];
      Result := Pss^.nBlockNumber;
    end;
  finally
    EndThreadSave;
  end;
end;

function TPCSafeBox.HasSnapshotForBlock(block_number: Cardinal): Boolean;
Var Pss : PSafeboxSnapshot;
  i : Integer;
begin
  Result := False;
  StartThreadSafe;
  Try
    i := FSnapshots.Count-1;
    while (i>=0) And (PSafeboxSnapshot( FSnapshots[i] )^.nBlockNumber<>block_number) do dec(i);
    Result := (i>=0);
  finally
    EndThreadSave;
  end;
end;

procedure TPCSafeBox.Clear;
Var i : Integer;
  P : PBlockAccount;
  Psnapshot : PSafeboxSnapshot;
begin
  StartThreadSafe;
  Try
    for i := 0 to FBlockAccountsList.Count - 1 do begin
      P := FBlockAccountsList.Items[i];
      Dispose(P);
    end;
    for i := 0 to FSnapshots.Count-1 do begin
      Psnapshot := (Fsnapshots[i]);
      FreeAndNil(Psnapshot^.oldBlocks);
      FreeAndNil(Psnapshot^.newBlocks);
      FreeAndNil(Psnapshot^.namesAdded);
      FreeAndNil(Psnapshot^.namesDeleted);
      Psnapshot^.oldBufferBlocksHash:='';
      Psnapshot^.oldSafeBoxHash:='';
      Dispose(Psnapshot);
    end;
    FSnapshots.Clear;
    FOrderedByName.Clear;
    FBlockAccountsList.Clear;
    For i:=0 to FListOfOrderedAccountKeysList.count-1 do begin
      TOrderedAccountKeysList( FListOfOrderedAccountKeysList[i] ).ClearAccounts(False);
    end;
    FBufferBlocksHash := '';
    FTotalBalance := 0;
    FTotalFee := 0;
    FSafeBoxHash := CalcSafeBoxHash;
    FWorkSum := 0;
    FCurrentProtocol := CT_PROTOCOL_1;
    FModifiedBlocksSeparatedChain.Clear;
    FModifiedBlocksFinalState.Clear;
    FModifiedBlocksPreviousState.Clear;
    FAddedNamesSincePreviousSafebox.Clear;
    FDeletedNamesSincePreviousSafebox.Clear;
  Finally
    EndThreadSave;
  end;
end;

procedure TPCSafeBox.CopyFrom(accounts: TPCSafeBox);
Var i,j : Cardinal;
  P : PBlockAccount;
  BA : TBlockAccount;
begin
  StartThreadSafe;
  Try
    accounts.StartThreadSafe;
    try
      if accounts=Self then exit;
      If (Assigned(FPreviousSafeBox)) then begin
        Raise Exception.Create('Safebox is a separated chain. Cannot copy from other Safebox');
      end;
      If (Assigned(accounts.FPreviousSafeBox)) then begin
        Raise Exception.Create('Cannot copy from a separated chain Safebox');
      end;
      Clear;
      if accounts.BlocksCount>0 then begin
        FBlockAccountsList.Capacity:=accounts.BlocksCount;
        for i := 0 to accounts.BlocksCount - 1 do begin
          BA := accounts.Block(i);
          New(P);
          ToTMemBlockAccount(BA,P^);
          FBlockAccountsList.Add(P);
          for j := Low(BA.accounts) to High(BA.accounts) do begin
            If (BA.accounts[j].name<>'') then FOrderedByName.Add(BA.accounts[j].name,BA.accounts[j].account);
            AccountKeyListAddAccounts(BA.accounts[j].accountInfo.accountKey,[BA.accounts[j].account]);
          end;
        end;
      end;
      FTotalBalance := accounts.TotalBalance;
      FTotalFee := accounts.FTotalFee;
      FBufferBlocksHash := accounts.FBufferBlocksHash;
      FSafeBoxHash := accounts.FSafeBoxHash;
      FWorkSum := accounts.FWorkSum;
      FCurrentProtocol := accounts.FCurrentProtocol;
    finally
      accounts.EndThreadSave;
    end;
  finally
    EndThreadSave;
  end;
end;

constructor TPCSafeBox.Create;
begin
  FMaxSafeboxSnapshots:=CT_DEFAULT_MaxSafeboxSnapshots;
  FLock := TPCCriticalSection.Create('TPCSafeBox_Lock');
  FBlockAccountsList := TList.Create;
  FListOfOrderedAccountKeysList := TList.Create;
  FCurrentProtocol := CT_PROTOCOL_1;
  FOrderedByName := TOrderedRawList.Create;
  FSnapshots := TList.Create;
  FPreviousSafeBox := Nil;
  FPreviousSafeboxOriginBlock := -1;
  FModifiedBlocksSeparatedChain := TOrderedBlockAccountList.Create;
  FModifiedBlocksPreviousState := TOrderedBlockAccountList.Create;
  FModifiedBlocksFinalState := TOrderedBlockAccountList.Create;
  FAddedNamesSincePreviousSafebox := TOrderedRawList.Create;
  FDeletedNamesSincePreviousSafebox := TOrderedRawList.Create;
  FSubChains := TList.Create;
  Clear;
end;

destructor TPCSafeBox.Destroy;
Var i : Integer;
begin
  Clear;
  // Skybuck: this should probably be done inside TOrderedAccountKeysList or so, but strange to put this here.
  // going to add a little method for this just in case
  for i := 0 to FListOfOrderedAccountKeysList.Count - 1 do begin
//    TOrderedAccountKeysList( FListOfOrderedAccountKeysList[i] ).FAccountList := Nil;
    TOrderedAccountKeysList( FListOfOrderedAccountKeysList[i] ).NillifyAccountList;
  end;
  FreeAndNil(FBlockAccountsList);
  FreeAndNil(FListOfOrderedAccountKeysList);
  FreeAndNil(FLock);
  FreeAndNil(FOrderedByName);
  FreeAndNil(FSnapshots);
  FreeAndNil(FModifiedBlocksSeparatedChain);
  FreeAndNil(FModifiedBlocksPreviousState);
  FreeAndNil(FModifiedBlocksFinalState);
  FreeAndNil(FAddedNamesSincePreviousSafebox);
  FreeAndNil(FDeletedNamesSincePreviousSafebox);
  FreeAndNil(FSubChains);
  If Assigned(FPreviousSafeBox) then begin
    FPreviousSafeBox.FSubChains.Remove(Self); // Remove from current snapshot
    FPreviousSafeBox := Nil;
    FPreviousSafeboxOriginBlock:=-1;
  end;
  inherited;
end;

procedure TPCSafeBox.SetToPrevious(APreviousSafeBox: TPCSafeBox; StartBlock: Cardinal);
Var i : Integer;
  Psnapshot : PSafeboxSnapshot;
begin
  StartThreadSafe;
  Try
    Clear;
    If Assigned(FPreviousSafeBox) then begin
      FPreviousSafeBox.FSubChains.Remove(Self); // Remove from current snapshot
      FPreviousSafeBox := Nil;
      FPreviousSafeboxOriginBlock:=-1;
    end;
    If Assigned(APreviousSafeBox) then begin
      APreviousSafeBox.StartThreadSafe;
      Try
        If (APreviousSafeBox = Self) then Raise Exception.Create('Invalid previous');
        If Assigned(APreviousSafebox.FPreviousSafeBox) then Raise Exception.Create('Previous safebox is based on a snapshot too'); // Limitation
        i := APreviousSafeBox.FSnapshots.Count-1;
        while (i>=0) And (PSafeboxSnapshot( APreviousSafeBox.FSnapshots[i] )^.nBlockNumber<>StartBlock) do dec(i);
        if (i<0) then begin
          Raise Exception.Create('Previous Safebox does not contain snapshot of block '+IntToStr(StartBlock));
        end;
        Psnapshot:=PSafeboxSnapshot( APreviousSafeBox.FSnapshots[i] );
        FPreviousSafeBox := APreviousSafeBox;
        FPreviousSafeboxOriginBlock:=StartBlock;
        //
        FPreviousSafeBox.FSubChains.Add(Self);
        //
        FBufferBlocksHash := Psnapshot^.oldBufferBlocksHash;
        FTotalBalance := Psnapshot^.oldTotalBalance;
        FTotalFee := Psnapshot^.oldTotalFee;
        FSafeBoxHash := Psnapshot^.oldSafeBoxHash;
        FWorkSum := Psnapshot^.oldWorkSum;
        FCurrentProtocol := Psnapshot^.oldCurrentProtocol;
      finally
        APreviousSafeBox.EndThreadSave;
      end;
    end else begin

    end;
  finally
    EndThreadSave;
  end;
end;

procedure TPCSafeBox.CommitToPrevious;
  procedure RedoModifiedBlocks(const modifiedblocks : TOrderedBlockAccountList);
  Var iBlock,j : Integer;
    blockAccount : TBlockAccount;
  begin
    // modifiedBlocks is sorted in ASCENDING order, will create a new block on FPreviousSafeBox when needed
    For iBlock := 0 to modifiedBlocks.Count-1 do begin
      blockAccount := modifiedBlocks.Get(iBlock);
      // Set each account to previous value:
      for j:=Low(blockAccount.accounts) to High(blockAccount.accounts) do begin
        FPreviousSafeBox.UpdateAccount(blockAccount.accounts[j].account,
          blockAccount.accounts[j].accountInfo,
          blockAccount.accounts[j].name,
          blockAccount.accounts[j].account_type,
          blockAccount.accounts[j].balance,
          blockAccount.accounts[j].n_operation,
          aus_commiting_from_otherchain,
          blockAccount.accounts[j].updated_block,
          blockAccount.accounts[j].previous_updated_block
          );
      end;
    end;
  end;
  Procedure RedoAddedDeletedNames(AddedNamesList,DeletedNamesList : TOrderedRawList);
  Var i : Integer;
  Begin
    // Start deleting:
    For i:=0 to DeletedNamesList.Count-1 do begin
      FPreviousSafebox.FOrderedByName.Remove(DeletedNamesList.Get(i));
    end;
    // Finally adding
    For i:=0 to AddedNamesList.Count-1 do begin
      FPreviousSafebox.FOrderedByName.Add(AddedNamesList.Get(i),AddedNamesList.GetTag(i));
    end;
    FPreviousSafebox.FAddedNamesSincePreviousSafebox.CopyFrom(AddedNamesList);
    FPreviousSafebox.FDeletedNamesSincePreviousSafebox.CopyFrom(DeletedNamesList);
  end;
  procedure RedoSnapshot(Psnapshot : PSafeboxSnapshot);
  Begin
    RedoModifiedBlocks(Psnapshot^.newBlocks);
    //
    RedoAddedDeletedNames(Psnapshot^.namesAdded,Psnapshot^.namesDeleted);
    //
    FPreviousSafeBox.AddNew(Block(Psnapshot^.nBlockNumber).blockchainInfo);
  end;

Var errors : AnsiString;
  i : Integer;
  Pss : PSafeboxSnapshot;
begin
  If Not Assigned(FPreviousSafeBox) then Raise Exception.Create('Previous not assigned');
  StartThreadSafe;
  Try
    FPreviousSafeBox.StartThreadSafe;
    Try
      { Process is:
        - Set Previous to snapshot state
        - for each snapshot:
           - update modified blocks
           - update Names lists with changes on snapshot
           - create a new block stored in snapshot
      }
      TLog.NewLog(ltdebug,ClassName,Format('Start CommitToPrevious - Rolling back from block %d to %d',[FPreviousSafeBox.BlocksCount-1,FPreviousSafeboxOriginBlock]));
      FPreviousSafeBox.RollBackToSnapshot(FPreviousSafeboxOriginBlock);
      {$IFDEF Check_Safebox_Names_Consistency}
      If Not Check_Safebox_Names_Consistency(FPreviousSafeBox,'PREVIOUS WITH ROLLBACK',errors) then begin
        TLog.NewLog(ltdebug,ClassName,'Check_Safebox_Names_Consistency '+errors);
      end;
      {$ENDIF}
      TLog.NewLog(ltdebug,ClassName,Format('Executing %d chain snapshots to master',[FSnapshots.Count]));
      For i:=0 to  FSnapshots.Count-1 do begin
        Pss := FSnapshots[i];
        TLog.NewLog(ltdebug,ClassName,Format('Executing %d/%d chain snapshot to master with %d blocks changed at block %d',[i+1,FSnapshots.Count,Pss^.newBlocks.Count,Pss^.nBlockNumber]));
        Try
          RedoSnapshot(Pss);
        Except
          On E:Exception do begin
            E.Message:= E.Message + Format(' Executing %d/%d chain snapshot to master with %d blocks changed at block %d',[i+1,FSnapshots.Count,Pss^.newBlocks.Count,Pss^.nBlockNumber]);
            Raise;
          end;
        end;
      end;
      // Finally add current changes?
      TLog.NewLog(ltdebug,ClassName,Format('Executing %d current chain changes to master',[FModifiedBlocksFinalState.Count]));
      RedoModifiedBlocks(FModifiedBlocksFinalState);
      RedoAddedDeletedNames(FAddedNamesSincePreviousSafebox,FDeletedNamesSincePreviousSafebox);

      TLog.NewLog(ltdebug,ClassName,Format('Check process start',[]));
      // Check it !!!!
      errors := '';
      If (FPreviousSafeBox.BlocksCount<>BlocksCount) then begin
        errors := errors+'> Invalid Blockscount!';
      end;
      If TBaseType.BinStrComp(FPreviousSafeBox.FSafeBoxHash,FSafeBoxHash)<>0 then begin
        errors := errors+'> Invalid SafeBoxHash!';
      end;
      If TBaseType.BinStrComp(FPreviousSafeBox.FBufferBlocksHash,FBufferBlocksHash)<>0 then begin
        errors := errors+'> Invalid BufferBlocksHash!';
      end;
      If (FPreviousSafeBox.FTotalBalance<>FTotalBalance) then begin
        errors := errors+'> Invalid Balance!';
      end;
      If (FPreviousSafeBox.FTotalFee<>FTotalFee) then begin
        errors := errors+'> Invalid Fee!';
      end;
      If (FPreviousSafeBox.WorkSum<>FWorkSum) then begin
        errors := errors+'> Invalid WorkSum!';
      end;
      If (FPreviousSafeBox.FCurrentProtocol<>FCurrentProtocol) then begin
        errors := errors+'> Invalid Protocol!';
      end;
      If (errors<>'') Then begin
        Raise Exception.Create('Errors Commiting to previous! '+errors);
      end;
      {$IFDEF Check_Safebox_Names_Consistency}
      If Not Check_Safebox_Names_Consistency(FPreviousSafeBox,'PREVIOUS',errors) then begin
        if errors='' then Raise Exception.Create('Check_Safebox_Names_Consistency '+errors);
      end;
      if Not Check_Safebox_Names_Consistency(Self,'CHAIN',errors) then begin
        if errors='' then Raise Exception.Create('Check_Safebox_Names_Consistency '+errors);
      end;
      Check_Safebox_Integrity(FPreviousSafeBox,'INTEGRITY PREVIOUS');
      Check_Safebox_Integrity(Self,'INTEGRITY CHAIN');
      {$ENDIF}
      TLog.NewLog(ltdebug,ClassName,Format('Check process end',[]));
    finally
      FPreviousSafeBox.EndThreadSave;
    end;
  finally
    EndThreadSave;
  end;
end;

procedure TPCSafeBox.RollBackToSnapshot(snapshotBlock: Cardinal);
   procedure UndoModifiedBlocks(modifiedblocks : TOrderedBlockAccountList);
   Var iBlock,j : Integer;
     blockAccount : TBlockAccount;
   begin
     For iBlock := 0 to modifiedBlocks.Count-1 do begin
       blockAccount := modifiedBlocks.Get(iBlock);
       // Set each account to previous value:
       for j:=Low(blockAccount.accounts) to High(blockAccount.accounts) do begin
         UpdateAccount(blockAccount.accounts[j].account,
           blockAccount.accounts[j].accountInfo,
           blockAccount.accounts[j].name,
           blockAccount.accounts[j].account_type,
           blockAccount.accounts[j].balance,
           blockAccount.accounts[j].n_operation,
           aus_rollback,
           blockAccount.accounts[j].updated_block,
           blockAccount.accounts[j].previous_updated_block
           );
       end;
     end;
   end;

   Procedure UndoAddedDeletedNames(AddedNamesList,DeletedNamesList : TOrderedRawList);
   Var i,j : Integer;
   Begin
     // Start adding
     For i:=0 to AddedNamesList.Count-1 do begin
       // It was added, so we MUST FIND on current names list
       If Not FOrderedByName.Find(AddedNamesList.Get(i),j) then begin
         // ERROR: It has been added, why we not found???
         If DeletedNamesList.Find(AddedNamesList.Get(i),j) then begin
         end else begin
           TLog.NewLog(lterror,ClassName,Format('ERROR DEV 20180319-1 Name %s not found at account:%d',[AddedNamesList.Get(i),AddedNamesList.GetTag(i)]));
         end;
       end else FOrderedByName.Delete(j);
     end;
     // Finally deleting
     For i:=0 to DeletedNamesList.Count-1 do begin
       // It has been deleted, we MUST NOT FIND on current names list
       If FOrderedByName.Find(DeletedNamesList.Get(i),j) then begin
         // It has been deleted... now is found
         If (FOrderedByName.GetTag(j)<>DeletedNamesList.GetTag(i)) then begin
           // ERROR: It has been deleted, why is found with another account???
           TLog.NewLog(lterror,ClassName,Format('ERROR DEV 20180319-2 Name %s found at account:%d <> saved account:%d',[DeletedNamesList.Get(i),DeletedNamesList.GetTag(i),FOrderedByName.GetTag(j)]));
         end;
       end;
       // Add with Info of previous account with name (saved at Tag value)
       FOrderedByName.Add(DeletedNamesList.Get(i),DeletedNamesList.GetTag(i));
     end;
   end;

Var i,iPrevSnapshotTarget : Integer;
  Psnapshot : PSafeboxSnapshot;
  PBlock : PBlockAccount;
begin
  StartThreadSafe;
  Try
    { Process is:
      - Find Previous snapshot (target)
      - Undo current pending operations
      - For each snapshot do
        - Undo snapshot operations
        - Undo created BlockAccount
      - At target snapshot:
        - Restore values
      - Clear data
      - Delete "future" snapshots
    }
    iPrevSnapshotTarget := FSnapshots.Count-1;
    while (iPrevSnapshotTarget>=0) And (PSafeboxSnapshot(FSnapshots[iPrevSnapshotTarget])^.nBlockNumber<>snapshotBlock) do Dec(iPrevSnapshotTarget);
    If (iPrevSnapshotTarget<0) then Raise Exception.Create('Cannot Rollback to previous Snapshot block: '+IntToStr(snapshotBlock)+' current '+IntToStr(BlocksCount));
    // Go back starting from current state
    UndoModifiedBlocks(FModifiedBlocksPreviousState);
    UndoAddedDeletedNames(FAddedNamesSincePreviousSafebox,FDeletedNamesSincePreviousSafebox);
    // Go back based on snapshots: EXCEPT target
    For i:=FSnapshots.Count-1 downto (iPrevSnapshotTarget+1) do begin
      Psnapshot := FSnapshots[i];
      TLog.NewLog(ltdebug,ClassName,Format('Executing %d/%d rollback %d blocks changed at block %d',[i+1,FSnapshots.Count,Psnapshot^.oldBlocks.Count,Psnapshot^.nBlockNumber]));

      // Must UNDO changes:
      UndoModifiedBlocks(Psnapshot^.oldBlocks);
      UndoAddedDeletedNames(Psnapshot^.namesAdded,Psnapshot^.namesDeleted);

      // Undo Created BlockAccount
      // Undo ONLY of if not target
      PBlock:=FBlockAccountsList.Items[FBlockAccountsList.Count-1];
      FBlockAccountsList.Delete(FBlockAccountsList.Count-1);
      Dispose(PBlock);

      // Redo FBufferBlocksHash
      SetLength(FBufferBlocksHash,Length(FBufferBlocksHash)-32);

      // Delete
      FSnapshots.Delete(i);
      Psnapshot^.oldBlocks.Free;
      Psnapshot^.newBlocks.Free;
      Psnapshot^.namesAdded.Free;
      Psnapshot^.namesDeleted.Free;
      Psnapshot^.oldBufferBlocksHash := '';
      Psnapshot^.oldSafeBoxHash := '';
      Dispose(Psnapshot);
    end;
    // Set saved Safebox values:
    Psnapshot := FSnapshots[iPrevSnapshotTarget];

    If TBaseType.BinStrComp(FBufferBlocksHash,Psnapshot^.oldBufferBlocksHash)<>0 then begin
      raise Exception.Create('ERROR DEV 20180322-1 Rollback invalid BufferBlocksHash value');
    end;

    FBufferBlocksHash := Psnapshot^.oldBufferBlocksHash;
    FTotalBalance := Psnapshot^.oldTotalBalance;
    FTotalFee := Psnapshot^.oldTotalFee;
    FSafeBoxHash := Psnapshot^.oldSafeBoxHash;
    FWorkSum := Psnapshot^.oldWorkSum;
    FCurrentProtocol := Psnapshot^.oldCurrentProtocol;
    // Clear data
    FAddedNamesSincePreviousSafebox.Clear;
    FDeletedNamesSincePreviousSafebox.Clear;
    FModifiedBlocksPreviousState.Clear;
    FModifiedBlocksFinalState.Clear;
    {$IFDEF Check_Safebox_Names_Consistency}
    if Not Check_Safebox_Names_Consistency(Self,'ROLLBACK',errors) then begin
      if errors='' then Raise Exception.Create('Check_Safebox_Names_Consistency '+errors);
    end;
    {$ENDIF}
  finally
    EndThreadSave;
  end;
end;

function TPCSafeBox.DoUpgradeToProtocol2: Boolean;
var block_number : Cardinal;
  aux : TRawBytes;
begin
  // Upgrade process to protocol 2
  Result := false;
  If Not CanUpgradeToProtocol(CT_PROTOCOL_2) then exit;
  // Recalc all BlockAccounts block_hash value
  aux := CalcSafeBoxHash;
  TLog.NewLog(ltInfo,ClassName,'Start Upgrade to protocol 2 - Old Safeboxhash:'+TCrypto.ToHexaString(FSafeBoxHash)+' calculated: '+TCrypto.ToHexaString(aux)+' Blocks: '+IntToStr(BlocksCount));
  FBufferBlocksHash:='';
  for block_number := 0 to BlocksCount - 1 do begin
    {$IFDEF uselowmem}
    TBaseType.To32Bytes(CalcBlockHash( Block(block_number), True),PBlockAccount(FBlockAccountsList.Items[block_number])^.block_hash);
    FBufferBlocksHash := FBufferBlocksHash+TBaseType.ToRawBytes(PBlockAccount(FBlockAccountsList.Items[block_number])^.block_hash);
    {$ELSE}
    PBlockAccount(FBlockAccountsList.Items[block_number])^.block_hash := CalcBlockHash( Block(block_number), True);
    FBufferBlocksHash := FBufferBlocksHash+PBlockAccount(FBlockAccountsList.Items[block_number])^.block_hash;
    {$ENDIF}
  end;
  FSafeBoxHash := CalcSafeBoxHash;
  FCurrentProtocol := CT_PROTOCOL_2;
  Result := True;
  TLog.NewLog(ltInfo,ClassName,'End Upgraded to protocol 2 - New safeboxhash:'+TCrypto.ToHexaString(FSafeBoxHash));
end;

function TPCSafeBox.DoUpgradeToProtocol3: Boolean;
begin
  FCurrentProtocol := CT_PROTOCOL_3;
  Result := True;
  TLog.NewLog(ltInfo,ClassName,'End Upgraded to protocol 3 - New safeboxhash:'+TCrypto.ToHexaString(FSafeBoxHash));
end;

procedure TPCSafeBox.EndThreadSave;
begin
  FLock.Release;
end;

function TPCSafeBox.LoadSafeBoxFromStream(Stream : TStream; checkAll : Boolean; var LastReadBlock : TBlockAccount; var errors : AnsiString) : Boolean;
Var
  iblock,iacc : Cardinal;
  s : AnsiString;
  block : TBlockAccount;
  P : PBlockAccount;
  i,j : Integer;
  savedSBH : TRawBytes;
  nPos,posOffsetZone : Int64;
  offsets : Array of Cardinal;
  sbHeader : TPCSafeBoxHeader;
begin
  If Assigned(FPreviousSafeBox) then Raise Exception.Create('Cannot loadSafeBoxFromStream on a Safebox in a Separate chain');
  StartThreadSafe;
  try
    Clear;
    Result := false;
    Try
      If not LoadSafeBoxStreamHeader(Stream,sbHeader) then begin
        errors := 'Invalid stream. Invalid header/version';
        exit;
      end;
      errors := 'Invalid version or corrupted stream';
      case sbHeader.protocol of
        CT_PROTOCOL_1 : FCurrentProtocol := 1;
        CT_PROTOCOL_2 : FCurrentProtocol := 2;
        CT_PROTOCOL_3 : FCurrentProtocol := 3;
      else exit;
      end;
      if (sbHeader.blocksCount=0) Or (sbHeader.startBlock<>0) Or (sbHeader.endBlock<>(sbHeader.blocksCount-1)) then begin
        errors := Format('Safebox Stream contains blocks from %d to %d (of %d blocks). Not valid',[sbHeader.startBlock,sbHeader.endBlock,sbHeader.blocksCount]);
        exit;
      end;
      // Offset zone
      posOffsetZone := Stream.Position;
      If checkAll then begin
        SetLength(offsets,sbHeader.blockscount+1); // Last offset = End of blocks
        Stream.Read(offsets[0],4*(sbHeader.blockscount+1));
      end else begin
        nPos := Stream.Position + ((sbHeader.blockscount+1) * 4);
        if Stream.Size<npos then exit;
        Stream.Position := nPos;
      end;
      // Build 1.3.0 to increase reading speed:
      FBlockAccountsList.Capacity := sbHeader.blockscount;
      SetLength(FBufferBlocksHash,sbHeader.blocksCount*32); // Initialize for high speed reading
      errors := 'Corrupted stream';
      for iblock := 0 to sbHeader.blockscount-1 do begin
        errors := 'Corrupted stream reading block blockchain '+inttostr(iblock+1)+'/'+inttostr(sbHeader.blockscount);
        if (checkAll) then begin
          If (offsets[iblock]<>Stream.Position-posOffsetZone) then begin
            errors := errors + Format(' - offset[%d]:%d <> %d Position:%d offset:%d',[iblock,offsets[iblock],Stream.Position-posOffsetZone,Stream.Position,posOffsetZone]);
            exit;
          end;
        end;

        block := CT_BlockAccount_NUL;
        If Not TAccountComp.LoadTOperationBlockFromStream(Stream,block.blockchainInfo) then exit;
        if block.blockchainInfo.block<>iBlock then exit;
        for iacc := Low(block.accounts) to High(block.accounts) do begin
          errors := 'Corrupted stream reading account '+inttostr(iacc+1)+'/'+inttostr(length(block.accounts))+' of block '+inttostr(iblock+1)+'/'+inttostr(sbHeader.blockscount);
          if Stream.Read(block.accounts[iacc].account,4)<4 then exit;
          if TStreamOp.ReadAnsiString(Stream,s)<0 then exit;
          block.accounts[iacc].accountInfo := TAccountComp.RawString2AccountInfo(s);
          if Stream.Read(block.accounts[iacc].balance,SizeOf(UInt64))<SizeOf(UInt64) then exit;
          if Stream.Read(block.accounts[iacc].updated_block,4)<4 then exit;
          if Stream.Read(block.accounts[iacc].n_operation,4)<4 then exit;
          If FCurrentProtocol>=CT_PROTOCOL_2 then begin
            if TStreamOp.ReadAnsiString(Stream,block.accounts[iacc].name)<0 then exit;
            if Stream.Read(block.accounts[iacc].account_type,2)<2 then exit;
          end;
          //
          if Stream.Read(block.accounts[iacc].previous_updated_block,4)<4 then exit;
          // check valid
          If (block.accounts[iacc].name<>'') then begin
            if FOrderedByName.IndexOf(block.accounts[iacc].name)>=0 then begin
              errors := errors + ' Duplicate name "'+block.accounts[iacc].name+'"';
              Exit;
            end;
            if Not TPCSafeBox.ValidAccountName(block.accounts[iacc].name,s) then begin
              errors := errors + ' > Invalid name "'+block.accounts[iacc].name+'": '+s;
              Exit;
            end;
            FOrderedByName.Add(block.accounts[iacc].name,block.accounts[iacc].account);
          end;
          If checkAll then begin
            if not TAccountComp.IsValidAccountInfo(block.accounts[iacc].accountInfo,s) then begin
              errors := errors + ' > '+s;
              Exit;
            end;
          end;
          FTotalBalance := FTotalBalance + block.accounts[iacc].balance;
        end;
        errors := 'Corrupted stream reading block '+inttostr(iblock+1)+'/'+inttostr(sbHeader.blockscount);
        If TStreamOp.ReadAnsiString(Stream,block.block_hash)<0 then exit;
        If Stream.Read(block.accumulatedWork,SizeOf(block.accumulatedWork)) < SizeOf(block.accumulatedWork) then exit;
        if checkAll then begin
          // Check is valid:
          // STEP 1: Validate the block
          If not IsValidNewOperationsBlock(block.blockchainInfo,False,s) then begin
            errors := errors + ' > ' + s;
            exit;
          end;
          // STEP 2: Check if valid block hash
          if CalcBlockHash(block,FCurrentProtocol>=CT_PROTOCOL_2)<>block.block_hash then begin
            errors := errors + ' > Invalid block hash '+inttostr(iblock+1)+'/'+inttostr(sbHeader.blockscount);
            exit;
          end;
          // STEP 3: Check accumulatedWork
          if (iblock>0) then begin
            If (self.Block(iblock-1).accumulatedWork)+block.blockchainInfo.compact_target <> block.accumulatedWork then begin
              errors := errors + ' > Invalid accumulatedWork';
              exit;
            end;
          end;
        end;
        // Add
        New(P);
        ToTMemBlockAccount(block,P^);
        FBlockAccountsList.Add(P);
        for j := low(block.accounts) to High(block.accounts) do begin
          AccountKeyListAddAccounts(block.accounts[j].accountInfo.accountKey,[block.accounts[j].account]);
        end;
        // BufferBlocksHash fill with data
        j := (length(P^.block_hash)*(iBlock));
        for i := 1 to length(P^.block_hash) do begin
          {$IFDEF FPC}
          FBufferBlocksHash[i+j] := AnsiChar(P^.block_hash[i-(low(FBufferBlocksHash)-low(P^.block_hash))]);
          {$ELSE}
          FBufferBlocksHash[i+j] := AnsiChar(P^.block_hash[i-{$IFDEF uselowmem}1{$ELSE}0{$ENDIF}]);
          {$ENDIF}
        end;
        LastReadBlock := block;
        FWorkSum := FWorkSum + block.blockchainInfo.compact_target;
      end;
      If checkAll then begin
        If (offsets[sbHeader.blockscount]<>0) And (offsets[sbHeader.blockscount]<>Stream.Position-posOffsetZone) then begin
          errors := errors + Format(' - Final offset[%d]=%d <> Eof Position:%d offset:%d',[sbHeader.blockscount,offsets[sbHeader.blockscount],Stream.Position-posOffsetZone,posOffsetZone]);
          exit;
        end;
      end;
      // Finally load SafeBoxHash
      If TStreamOp.ReadAnsiString(stream,savedSBH)<0 then begin
        errors := 'No SafeBoxHash value';
        exit;
      end;
      // Check worksum value
      If sbHeader.blockscount>0 then begin
        If (FWorkSum<>Self.Block(sbHeader.blockscount-1).accumulatedWork) then begin
          errors := 'Invalid WorkSum value';
          exit;
        end;
      end;
      // Calculating safe box hash
      FSafeBoxHash := CalcSafeBoxHash;
      // Checking saved SafeBoxHash
      If FSafeBoxHash<>savedSBH then begin
        errors := 'Invalid SafeBoxHash value in stream '+TCrypto.ToHexaString(FSafeBoxHash)+'<>'+TCrypto.ToHexaString(savedSBH)+' Last block:'+IntToStr(LastReadBlock.blockchainInfo.block);
        exit;
      end;
      Result := true;
    Finally
      if Not Result then Clear else errors := '';
    End;
  Finally
    EndThreadSave;
  end;
end;

class function TPCSafeBox.LoadSafeBoxStreamHeader(Stream: TStream; var sbHeader : TPCSafeBoxHeader) : Boolean;
  // This function reads SafeBox stream info and sets position at offset start zone if valid, otherwise sets position to actual position
Var w : Word;
  s : AnsiString;
  safeBoxBankVersion : Word;
  offsetPos, initialPos  : Int64;
  endBlocks : Cardinal;
begin
  Result := false;
  sbHeader := CT_PCSafeBoxHeader_NUL;
  initialPos := Stream.Position;
  try
    TStreamOp.ReadAnsiString(Stream,s);
    if (s<>CT_MagicIdentificator) then exit;
    if Stream.Size<8 then exit;
    Stream.Read(w,SizeOf(w));
    if not (w in [CT_PROTOCOL_1,CT_PROTOCOL_2,CT_PROTOCOL_3]) then exit;
    sbHeader.protocol := w;
    Stream.Read(safeBoxBankVersion,2);
    if safeBoxBankVersion<>CT_SafeBoxBankVersion then exit;
    Stream.Read(sbHeader.blocksCount,4);
    Stream.Read(sbHeader.startBlock,4);
    Stream.Read(sbHeader.endBlock,4);
    if (sbHeader.blocksCount<=0) Or (sbHeader.blocksCount>(CT_NewLineSecondsAvg*2000000)) then exit; // Protection for corrupted data...
    offsetPos := Stream.Position;
    // Go to read SafeBoxHash
    If (Stream.size<offsetPos + (((sbHeader.endBlock - sbHeader.startBlock)+2)*4)) then exit;
    Stream.position := offsetPos + (((sbHeader.endBlock - sbHeader.startBlock)+1)*4);
    Stream.Read(endBlocks,4);
    // Go to end
    If (Stream.Size<offsetPos + (endBlocks)) then exit;
    Stream.Position:=offsetPos + endBlocks;
    If TStreamOp.ReadAnsiString(Stream,sbHeader.safeBoxHash)<0 then exit;
    // Back
    Stream.Position:=offsetPos;
    Result := True;
  finally
    If not Result then Stream.Position := initialPos;
  end;
end;

class function TPCSafeBox.SaveSafeBoxStreamHeader(Stream: TStream;
  protocol: Word; OffsetStartBlock, OffsetEndBlock,
  CurrentSafeBoxBlocksCount: Cardinal): Boolean;
var c : Cardinal;
begin
  Result := False;
  // Header zone
  TStreamOp.WriteAnsiString(Stream,CT_MagicIdentificator);
  Stream.Write(protocol,SizeOf(protocol));
  Stream.Write(CT_SafeBoxBankVersion,SizeOf(CT_SafeBoxBankVersion));
  c := CurrentSafeBoxBlocksCount;
  Stream.Write(c,Sizeof(c)); // Save Total blocks of the safebox
  c := OffsetStartBlock;
  Stream.Write(c,Sizeof(c)); // Save first block saved
  c := OffsetEndBlock;
  Stream.Write(c,Sizeof(c)); // Save last block saved
  Result := True;
end;

class function TPCSafeBox.MustSafeBoxBeSaved(BlocksCount: Cardinal): Boolean;
begin
  Result := (BlocksCount MOD CT_BankToDiskEveryNBlocks)=0;
end;

procedure TPCSafeBox.SaveSafeBoxBlockToAStream(Stream: TStream; nBlock: Cardinal);
var b : TBlockAccount;
  iacc : integer;
begin
  b := Block(nblock);
  TAccountComp.SaveTOperationBlockToStream(Stream,b.blockchainInfo);
  for iacc := Low(b.accounts) to High(b.accounts) do begin
    Stream.Write(b.accounts[iacc].account,Sizeof(b.accounts[iacc].account));
    TStreamOp.WriteAnsiString(Stream,TAccountComp.AccountInfo2RawString(b.accounts[iacc].accountInfo));
    Stream.Write(b.accounts[iacc].balance,Sizeof(b.accounts[iacc].balance));
    Stream.Write(b.accounts[iacc].updated_block,Sizeof(b.accounts[iacc].updated_block));
    Stream.Write(b.accounts[iacc].n_operation,Sizeof(b.accounts[iacc].n_operation));
    If FCurrentProtocol>=CT_PROTOCOL_2 then begin
      TStreamOp.WriteAnsiString(Stream,b.accounts[iacc].name);
      Stream.Write(b.accounts[iacc].account_type,SizeOf(b.accounts[iacc].account_type));
    end;
    Stream.Write(b.accounts[iacc].previous_updated_block,Sizeof(b.accounts[iacc].previous_updated_block));
  end;
  TStreamOp.WriteAnsiString(Stream,b.block_hash);
  Stream.Write(b.accumulatedWork,Sizeof(b.accumulatedWork));
end;

procedure TPCSafeBox.SaveSafeBoxToAStream(Stream: TStream; FromBlock, ToBlock : Cardinal);
Var
  totalBlocks,iblock : Cardinal;
  b : TBlockAccount;
  posOffsetZone, posFinal : Int64;
  offsets : TCardinalsArray;
  raw : TRawBytes;
begin
  If (FromBlock>ToBlock) Or (ToBlock>=BlocksCount) then Raise Exception.Create(Format('Cannot save SafeBox from %d to %d (currently %d blocks)',[FromBlock,ToBlock,BlocksCount]));
  StartThreadSafe;
  Try
    // Header zone
    SaveSafeBoxStreamHeader(Stream,FCurrentProtocol,FromBlock,ToBlock,BlocksCount);
    totalBlocks := ToBlock - FromBlock + 1;
    // Offsets zone
    posOffsetZone:=Stream.Position;
    SetLength(raw,(totalBlocks+1)*4); // Last position = end
    FillChar(raw[1],length(raw),0);
    Stream.WriteBuffer(raw[1],length(raw));
    setLength(offsets,totalBlocks+1); // c = total blocks  - Last position = offset to end
    // Blocks zone
    for iblock := FromBlock to ToBlock do begin
      offsets[iBlock] := Stream.Position - posOffsetZone;
      SaveSafeBoxBlockToAStream(Stream,iblock);
    end;
    offsets[High(offsets)] := Stream.Position - posOffsetZone;
    // Save offsets zone with valid values
    posFinal := Stream.Position;
    Stream.Position := posOffsetZone;
    for iblock := FromBlock to ToBlock+1 do begin
      Stream.Write(offsets[iblock],SizeOf(offsets[iblock]));
    end;
    Stream.Position := posFinal;
    // Final zone: Save safeboxhash for next block
    If (ToBlock+1<BlocksCount) then begin
      b := Block(ToBlock);
      TStreamOp.WriteAnsiString(Stream,b.blockchainInfo.initial_safe_box_hash);
    end else begin
      TStreamOp.WriteAnsiString(Stream,FSafeBoxHash);
    end;
  Finally
    EndThreadSave;
  end;
end;

class function TPCSafeBox.CopySafeBoxStream(Source, Dest: TStream; FromBlock,ToBlock: Cardinal; var errors : AnsiString) : Boolean;
Var
  iblock : Cardinal;
  raw : TRawBytes;
  posOffsetZoneSource, posOffsetZoneDest, posFinal, posBlocksZoneDest, posInitial : Int64;
  offsetsSource,offsetsDest : TCardinalsArray;
  destTotalBlocks : Cardinal;
  sbHeader : TPCSafeBoxHeader;
begin
  Result := False; errors := '';
  posInitial := Source.Position;
  try
    If (FromBlock>ToBlock) then begin
      errors := Format('Invalid CopySafeBoxStream(from %d, to %d)',[FromBlock,ToBlock]);
      exit;
    end;
    If not LoadSafeBoxStreamHeader(Source,sbHeader) then begin
      errors := 'Invalid stream. Invalid header/version';
      exit;
    end;
    if (sbHeader.startBlock>FromBlock) Or (sbHeader.endBlock<ToBlock) Or ((sbHeader.startBlock + sbHeader.blocksCount)<ToBlock) then begin
      errors := Format('Stream contain blocks from %d to %d (of %d). Need between %d and %d !',[sbHeader.startBlock,sbHeader.endBlock,sbHeader.blocksCount,FromBlock,ToBlock]);
      exit;
    end;
    destTotalBlocks := ToBlock - FromBlock + 1;
    TLog.NewLog(ltDebug,ClassName,Format('CopySafeBoxStream from safebox with %d to %d (of %d sbh:%s) to safebox with %d and %d',
      [sbHeader.startBlock,sbHeader.endBlock,sbHeader.BlocksCount,TCrypto.ToHexaString(sbHeader.safeBoxHash),FromBlock,ToBlock]));
    // Read Source Offset zone
    posOffsetZoneSource := Source.Position;
    SetLength(offsetsSource,(sbHeader.endBlock-sbHeader.startBlock)+2);
    Source.Read(offsetsSource[0],4*length(offsetsSource));
    // DEST STREAM:
    // Init dest stream
    // Header zone
    SaveSafeBoxStreamHeader(Dest,sbHeader.protocol,FromBlock,ToBlock,sbHeader.blocksCount);
    // Offsets zone
    posOffsetZoneDest:=Dest.Position;
    SetLength(raw,(destTotalBlocks+1)*4); // Cardinal = 4 bytes for each block + End position
    FillChar(raw[1],length(raw),0);
    Dest.WriteBuffer(raw[1],length(raw));
    setLength(offsetsDest,destTotalBlocks+1);
    // Blocks zone
    posBlocksZoneDest := Dest.Position;
    TLog.NewLog(ltDebug,Classname,
      Format('Copying Safebox Stream from source Position %d (size:%d) to dest %d bytes - OffsetSource[%d] - OffsetSource[%d]',
       [posOffsetZoneSource + offsetsSource[FromBlock - sbHeader.startBlock], Source.Size,
        offsetsSource[ToBlock - sbHeader.startBlock + 1] - offsetsSource[FromBlock - sbHeader.startBlock],
        ToBlock - sbHeader.startBlock + 1, FromBlock - sbHeader.startBlock
        ]));

    Source.Position:=posOffsetZoneSource + offsetsSource[FromBlock - sbHeader.startBlock];
    Dest.CopyFrom(Source,offsetsSource[ToBlock - sbHeader.startBlock + 1] - offsetsSource[FromBlock - sbHeader.startBlock]);
    // Save offsets zone with valid values
    posFinal := Dest.Position;
    Dest.Position := posOffsetZoneDest;
    for iblock := FromBlock to ToBlock do begin
      offsetsDest[iblock - FromBlock] := offsetsSource[iblock - (sbHeader.startBlock)] - offsetsSource[FromBlock - sbHeader.startBlock] + (posBlocksZoneDest - posOffsetZoneDest);
    end;
    offsetsDest[high(offsetsDest)] := posFinal - posOffsetZoneDest;

    Dest.WriteBuffer(offsetsDest[0],length(offsetsDest)*4);
    Dest.Position := posFinal;
    Source.Position := offsetsSource[High(offsetsSource)] + posOffsetZoneSource;
    TStreamOp.ReadAnsiString(Source,raw);
    TStreamOp.WriteAnsiString(Dest,raw);
    Result := true;
  finally
    Source.Position:=posInitial;
  end;
end;

class function TPCSafeBox.ConcatSafeBoxStream(Source1, Source2, Dest: TStream; var errors: AnsiString): Boolean;
  function MinCardinal(v1,v2 : Cardinal) : Cardinal;
  begin
    if v1<v2 then Result:=v1
    else Result:=v2;
  end;
  function MaxCardinal(v1,v2 : Cardinal) : Cardinal;
  begin
    if v1>v2 then Result:=v1
    else Result:=v2;
  end;
  function ReadSafeBoxBlockFromStream(safeBoxStream : TStream; offsetIndex : Cardinal; destStream : TStream) : Cardinal;
    // PRE: safeBoxStream is a valid SafeBox Stream (with enough size) located at Offsets zone, and offsetIndex is >=0 and <= end block
    // Returns the size of the saved block at destStream
  var offsetPos, auxPos : Int64;
    c,cNext : Cardinal;
  begin
    Result := 0;
    offsetPos := safeBoxStream.Position;
    try
      safeBoxStream.Seek(4*offsetIndex,soFromCurrent);
      safeBoxStream.Read(c,4);
      safeBoxStream.Read(cNext,4);
      if cNext<c then exit;
      Result := cNext - c; // Result is the offset difference between blocks
      if Result<=0 then exit;
      auxPos := offsetPos + c;
      if safeBoxStream.Size<auxPos+Result then exit; // Invalid
      safeBoxStream.Position:=auxPos;
      destStream.CopyFrom(safeBoxStream,Result);
    finally
      safeBoxStream.Position:=offsetPos;
    end;
  end;

  procedure WriteSafeBoxBlockToStream(Stream, safeBoxStream : TStream; nBytes : Integer; offsetIndex, totalOffsets : Cardinal);
  // PRE: safeBoxStream is a valid SafeBox Stream located at Offsets zone, and offsetIndex=0 or offsetIndex-1 has a valid value
  var offsetPos : Int64;
    c,cLength : Cardinal;
  begin
    offsetPos := safeBoxStream.Position;
    try
      if offsetIndex=0 then begin
        // First
        c := ((totalOffsets+1)*4);
        safeBoxStream.Write(c,4);
      end else begin
        safeBoxStream.Seek(4*(offsetIndex),soFromCurrent);
        safeBoxStream.Read(c,4); // c is position
      end;
      cLength := c + nBytes;
      safeBoxStream.Write(cLength,4);
      safeBoxStream.Position := offsetPos + c;
      safeBoxStream.CopyFrom(Stream,nBytes);
    finally
      safeBoxStream.Position:=offsetPos;
    end;
  end;

Var destStartBlock, destEndBlock, nBlock : Cardinal;
  source1InitialPos, source2InitialPos,
  destOffsetPos: Int64;
  ms : TMemoryStream;
  c : Cardinal;
  destOffsets : TCardinalsArray;
  i : Integer;
  s1Header,s2Header : TPCSafeBoxHeader;
begin
  Result := False; errors := '';
  source1InitialPos:=Source1.Position;
  source2InitialPos:=Source2.Position;
  Try
    If not LoadSafeBoxStreamHeader(Source1,s1Header) then begin
      errors := 'Invalid source 1 stream. Invalid header/version';
      exit;
    end;
    If not LoadSafeBoxStreamHeader(Source2,s2Header) then begin
      errors := 'Invalid source 2 stream. Invalid header/version';
      exit;
    end;
    // Check SBH and blockcount
    if (s1Header.safeBoxHash<>s2Header.safeBoxHash) or (s1Header.blocksCount<>s2Header.blocksCount) Or (s1Header.protocol<>s2Header.protocol) then begin
      errors := Format('Source1 and Source2 have diff safebox. Source 1 %d %s (protocol %d) Source 2 %d %s (protocol %d)',
       [s1Header.blocksCount,TCrypto.ToHexaString(s1Header.safeBoxHash),s1Header.protocol,
        s2Header.blocksCount,TCrypto.ToHexaString(s2Header.safeBoxHash),s2Header.protocol]);
      exit;
    end;
    // Save dest heaer
    destStartBlock := MinCardinal(s1Header.startBlock,s2Header.startBlock);
    destEndBlock := MaxCardinal(s1Header.endBlock,s2Header.endBlock);
    SaveSafeBoxStreamHeader(Dest,s1Header.protocol,destStartBlock,destEndBlock,s1Header.blocksCount);
    // Save offsets
    destOffsetPos:=Dest.Position;
    SetLength(destOffsets,((destEndBlock-destStartBlock)+2));
    for i:=low(destOffsets) to high(destOffsets) do destOffsets[i] := 0;
    Dest.Write(destOffsets[0],((destEndBlock-destStartBlock)+2)*4);
    Dest.Position:=destOffsetPos;
    //
    nBlock := destStartBlock;
    ms := TMemoryStream.Create;
    try
      for nBlock :=destStartBlock to destEndBlock do begin
        ms.Clear;
        if (nBlock>=s1Header.startBlock) And (nBlock<=s1Header.endBlock) then begin
          c := ReadSafeBoxBlockFromStream(Source1,nBlock-s1Header.startBlock,ms);
          ms.Position:=0;
          WriteSafeBoxBlockToStream(ms,Dest,c,nBlock-destStartBlock,destEndBlock-destStartBlock+1);
        end else if (nBlock>=s2Header.startBlock) and (nBlock<=s2Header.endBlock) then begin
          c := ReadSafeBoxBlockFromStream(Source2,nBlock-s2Header.startBlock,ms);
          ms.Position:=0;
          WriteSafeBoxBlockToStream(ms,Dest,c,nBlock-destStartBlock,destEndBlock-destStartBlock+1);
        end else Raise Exception.Create('ERROR DEV 20170518-1');
      end;
    Finally
      ms.Free;
    end;
    // Save SafeBoxHash at the end
    Dest.Seek(0,soFromEnd);
    TStreamOp.WriteAnsiString(Dest,s1Header.safeBoxHash);
    Result := true;
  Finally
    Source1.Position:=source1InitialPos;
    Source2.Position:=source2InitialPos;
  end;
end;

class function TPCSafeBox.ValidAccountName(const new_name: TRawBytes; var errors : AnsiString): Boolean;
  { Note:
    This function is case senstive, and only lower case chars are valid.
    Execute a LowerCase() prior to call this function!
    }
Const CT_PascalCoin_Base64_Charset : ShortString = 'abcdefghijklmnopqrstuvwxyz0123456789!@#$%^&*()-+{}[]\_:"|<>,.?/~';
      // First char can't start with a number
      CT_PascalCoin_FirstChar_Charset : ShortString = 'abcdefghijklmnopqrstuvwxyz!@#$%^&*()-+{}[]\_:"|<>,.?/~';
      CT_PascalCoin_name_min_length = 3;
      CT_PascalCoin_name_max_length = 64;
var i,j : Integer;
begin
  Result := False; errors := '';
  if (length(new_name)<CT_PascalCoin_name_min_length) Or (length(new_name)>CT_PascalCoin_name_max_length) then begin
    errors := 'Invalid length:'+IntToStr(Length(new_name))+' (valid from '+Inttostr(CT_PascalCoin_name_max_length)+' to '+IntToStr(CT_PascalCoin_name_max_length)+')';
    Exit;
  end;
  for i:=1 to length(new_name) do begin
    j:=1;
    if (i=1) then begin
      // First char can't start with a number
      While (j<=length(CT_PascalCoin_FirstChar_Charset)) and (new_name[i]<>CT_PascalCoin_FirstChar_Charset[j]) do inc(j);
      if j>length(CT_PascalCoin_FirstChar_Charset) then begin
        errors := 'Invalid char '+new_name[i]+' at first pos';
        Exit; // Not found
      end;
    end else begin
      While (j<=length(CT_PascalCoin_Base64_Charset)) and (new_name[i]<>CT_PascalCoin_Base64_Charset[j]) do inc(j);
      if j>length(CT_PascalCoin_Base64_Charset) then begin
        errors := 'Invalid char '+new_name[i]+' at pos '+IntToStr(i);
        Exit; // Not found
      end;
    end;
  end;
  Result := True;
end;

function TPCSafeBox.IsValidNewOperationsBlock(const newOperationBlock: TOperationBlock; checkSafeBoxHash : Boolean; var errors: AnsiString): Boolean;
  { This function will check a OperationBlock info as a valid candidate to be included in the safebox

    TOperationBlock contains the info of the new block EXCEPT the operations, including only operations_hash value (SHA256 of the Operations)
    So, cannot check operations and fee values
  }
var target_hash, pow : TRawBytes;
  i : Integer;
  lastBlock : TOperationBlock;
begin
  Result := False;
  errors := '';
  If BlocksCount>0 then lastBlock := Block(BlocksCount-1).blockchainInfo
  else lastBlock := CT_OperationBlock_NUL;
  // Check block
  if (BlocksCount <> newOperationBlock.block) then begin
    errors := 'block ('+inttostr(newOperationBlock.block)+') is not new position ('+inttostr(BlocksCount)+')';
    exit;
  end;

  // fee: Cannot be checked only with the safebox
  // protocol available is not checked
  if (newOperationBlock.block > 0) then begin
    // protocol
    if (newOperationBlock.protocol_version<>CurrentProtocol) then begin
      // Protocol must be 1 or 2. If 1 then all prior blocksmust be 1 and never 2 (invalide blockchain version scenario v1...v2...v1)
      If (lastBlock.protocol_version>newOperationBlock.protocol_version) then begin
        errors := 'Invalid PascalCoin protocol version: '+IntToStr( newOperationBlock.protocol_version )+' Current: '+IntToStr(CurrentProtocol)+' Previous:'+IntToStr(lastBlock.protocol_version);
        exit;
      end;
      If (newOperationBlock.protocol_version=CT_PROTOCOL_3) then begin
        If (newOperationBlock.block<CT_Protocol_Upgrade_v3_MinBlock) then begin
          errors := 'Upgrade to protocol version 3 available at block: '+IntToStr(CT_Protocol_Upgrade_v3_MinBlock);
          exit;
        end;
      end else If (newOperationBlock.protocol_version=CT_PROTOCOL_2) then begin
        If (newOperationBlock.block<CT_Protocol_Upgrade_v2_MinBlock) then begin
          errors := 'Upgrade to protocol version 2 available at block: '+IntToStr(CT_Protocol_Upgrade_v2_MinBlock);
          exit;
        end;
      end else if (newOperationBlock.protocol_version<>CT_PROTOCOL_1) then begin
        errors := 'Invalid protocol version change to '+IntToStr(newOperationBlock.protocol_version);
        exit;
      end;
    end;
    // timestamp
    if ((newOperationBlock.timestamp) < (lastBlock.timestamp)) then begin
      errors := 'Invalid timestamp (Back timestamp: New timestamp:'+inttostr(newOperationBlock.timestamp)+' < last timestamp ('+Inttostr(BlocksCount-1)+'):'+Inttostr(lastBlock.timestamp)+')';
      exit;
    end;
  end;
  // compact_target
  target_hash:=GetActualTargetHash(newOperationBlock.protocol_version);
  if (newOperationBlock.compact_target <> TPascalCoinProtocol.TargetToCompact(target_hash)) then begin
    errors := 'Invalid target found:'+IntToHex(newOperationBlock.compact_target,8)+' actual:'+IntToHex(TPascalCoinProtocol.TargetToCompact(target_hash),8);
    exit;
  end;
  // initial_safe_box_hash: Only can be checked when adding new blocks, not when restoring a safebox
  If checkSafeBoxHash then begin
    // TODO: Can use FSafeBoxHash instead of CalcSafeBoxHash ???? Quick speed if possible
    if (newOperationBlock.initial_safe_box_hash <> CalcSafeBoxHash) then begin
      errors := 'BlockChain Safe box hash invalid: '+TCrypto.ToHexaString(newOperationBlock.initial_safe_box_hash)+' var: '+
        TCrypto.ToHexaString(FSafeBoxHash)+
        ' Calculated:'+TCrypto.ToHexaString(CalcSafeBoxHash);
      exit;
    end;
  end;
  {$IFnDEF TESTING_NO_POW_CHECK}
  if (newOperationBlock.proof_of_work > target_hash) then begin
    errors := 'Proof of work is higher than target '+TCrypto.ToHexaString(newOperationBlock.proof_of_work)+' > '+TCrypto.ToHexaString(target_hash);
    exit;
  end;
  {$ENDIF}
  Result := IsValidOperationBlock(newOperationBlock,errors);
end;

class function TPCSafeBox.IsValidOperationBlock(const newOperationBlock: TOperationBlock; var errors: AnsiString): Boolean;
  { This class function will check a OperationBlock basic info as a valid info

    Creted at Build 2.1.7 as a division of IsValidNewOperationsBlock for easily basic check TOperationBlock

    TOperationBlock contains the info of the new block, but cannot be checked with current Safebox state
    (Use IsValidNewOperationsBlock instead) and also cannot check operations, operations_hash, fees...
  }
var pow : TRawBytes;
  i : Integer;
begin
  Result := False;
  errors := '';
  // Check Account key
  if Not TAccountComp.IsValidAccountKey(newOperationBlock.account_key,errors) then begin
    exit;
  end;
  // reward
  if (newOperationBlock.reward<>TPascalCoinProtocol.GetRewardForNewLine(newOperationBlock.block)) then begin
    errors := 'Invalid reward';
    exit;
  end;
  // Valid protocol version
  if (Not (newOperationBlock.protocol_version in [CT_PROTOCOL_1,CT_PROTOCOL_2,CT_PROTOCOL_3])) then begin
    errors := 'Invalid protocol version '+IntToStr(newOperationBlock.protocol_version);
    exit;
  end;
  // fee: Cannot be checked only with the safebox
  // protocol available is not checked
  if (newOperationBlock.block > 0) then begin
  end else begin
    if (CT_Zero_Block_Proof_of_work_in_Hexa<>'') then begin
      // Check if valid Zero block
      if Not (AnsiSameText(TCrypto.ToHexaString(newOperationBlock.proof_of_work),CT_Zero_Block_Proof_of_work_in_Hexa)) then begin
        errors := 'Zero block not valid, Proof of Work invalid: '+TCrypto.ToHexaString(newOperationBlock.proof_of_work)+'<>'+CT_Zero_Block_Proof_of_work_in_Hexa;
        exit;
      end;
    end;
  end;
  // Checking Miner Payload valid chars/length
  If Not TPascalCoinProtocol.IsValidMinerBlockPayload(newOperationBlock.block_payload) then begin
    errors := 'Invalid Miner Payload value. Length: '+inttostr(Length(newOperationBlock.block_payload));
    exit;
  end;
  // operations_hash: NOT CHECKED WITH OPERATIONS!
  If (length(newOperationBlock.operations_hash)<>32) then begin
    errors := 'Invalid Operations hash value: '+TCrypto.ToHexaString(newOperationBlock.operations_hash)+' length='+IntToStr(Length(newOperationBlock.operations_hash));
    exit;
  end;
  // proof_of_work:
  {$IFnDEF TESTING_NO_POW_CHECK}
  TPascalCoinProtocol.CalcProofOfWork(newOperationBlock,pow);
  if (pow<>newOperationBlock.proof_of_work) then begin
    errors := 'Proof of work is bad calculated '+TCrypto.ToHexaString(newOperationBlock.proof_of_work)+' <> Good: '+TCrypto.ToHexaString(pow);
    exit;
  end;
  {$ENDIF}
  Result := true;
end;

function TPCSafeBox.GetActualTargetHash(protocolVersion : Word): TRawBytes;
{ Target is calculated in each block with avg obtained in previous
  CT_CalcNewDifficulty blocks.
  If Block is lower than CT_CalcNewDifficulty then is calculated
  with all previous blocks.
}
Var ts1, ts2, tsTeorical, tsReal, tsTeoricalStop, tsRealStop: Int64;
  CalcBack : Integer;
  lastBlock : TOperationBlock;
begin
  if (BlocksCount <= 1) then begin
    // Important: CT_MinCompactTarget is applied for blocks 0 until ((CT_CalcNewDifficulty*2)-1)
    Result := TPascalCoinProtocol.TargetFromCompact(CT_MinCompactTarget);
  end else begin
    if BlocksCount > CT_CalcNewTargetBlocksAverage then CalcBack := CT_CalcNewTargetBlocksAverage
    else CalcBack := BlocksCount-1;
    lastBlock := Block(BlocksCount-1).blockchainInfo;
    // Calc new target!
    ts1 := lastBlock.timestamp;
    ts2 := Block(BlocksCount-CalcBack-1).blockchainInfo.timestamp;
    tsTeorical := (CalcBack * CT_NewLineSecondsAvg);
    tsReal := (ts1 - ts2);
    If (protocolVersion=CT_PROTOCOL_1) then begin
      Result := TPascalCoinProtocol.GetNewTarget(tsTeorical, tsReal,protocolVersion,False,TPascalCoinProtocol.TargetFromCompact(lastBlock.compact_target));
    end else if (protocolVersion<=CT_PROTOCOL_3) then begin
      CalcBack := CalcBack DIV CT_CalcNewTargetLimitChange_SPLIT;
      If CalcBack=0 then CalcBack := 1;
      ts2 := Block(BlocksCount-CalcBack-1).blockchainInfo.timestamp;
      tsTeoricalStop := (CalcBack * CT_NewLineSecondsAvg);
      tsRealStop := (ts1 - ts2);
      { Protocol 2 change:
        Only will increase/decrease Target if (CT_CalcNewTargetBlocksAverage DIV 10) needs to increase/decrease too, othewise use
        current Target.
        This will prevent sinusoidal movement and provide more stable hashrate, computing always time from CT_CalcNewTargetBlocksAverage }
      If ((tsTeorical>tsReal) and (tsTeoricalStop>tsRealStop))
         Or
         ((tsTeorical<tsReal) and (tsTeoricalStop<tsRealStop)) then begin
        Result := TPascalCoinProtocol.GetNewTarget(tsTeorical, tsReal,protocolVersion,False,TPascalCoinProtocol.TargetFromCompact(lastBlock.compact_target));
      end else begin
        if (protocolVersion=CT_PROTOCOL_2) then begin
          // Nothing to do!
          Result:=TPascalCoinProtocol.TargetFromCompact(lastBlock.compact_target);
        end else begin
          // New on V3 protocol:
          // Harmonization of the sinusoidal effect modifying the rise / fall over the "stop" area
          Result := TPascalCoinProtocol.GetNewTarget(tsTeoricalStop,tsRealStop,protocolVersion,True,TPascalCoinProtocol.TargetFromCompact(lastBlock.compact_target));
        end;
      end;
    end else begin
      Raise Exception.Create('ERROR DEV 20180306-1 Protocol not valid');
    end;
  end;
end;

function TPCSafeBox.GetActualCompactTargetHash(protocolVersion : Word): Cardinal;
begin
  Result := TPascalCoinProtocol.TargetToCompact(GetActualTargetHash(protocolVersion));
end;

function TPCSafeBox.FindAccountByName(aName: AnsiString): Integer;
Var nameLower : AnsiString;
  i,j,k : Integer;
  Psnapshot : PSafeboxSnapshot;
begin
  nameLower := LowerCase(aName);
  i := FOrderedByName.IndexOf(nameLower);
  if i>=0 then Result := FOrderedByName.GetTag(i)
  else begin
    Result := -1;
    If Assigned(FPreviousSafeBox) then begin
      // Now doesn't exists, was deleted before?
      Result := FPreviousSafeBox.FindAccountByName(nameLower);
      j := FPreviousSafeBox.FSnapshots.Count-1;
      // Start with current changes on FPreviousSafebox
      // Start with Added
      If (Result>=0) then begin
        k := FPreviousSafeBox.FAddedNamesSincePreviousSafebox.IndexOf(nameLower);
        If (k>=0) then Result := -1;
      end;
      // Then with deleted
      If (Result<0) then begin
        // I've not found nameLower, search if was deleted
        k := (FPreviousSafeBox.FDeletedNamesSincePreviousSafebox.IndexOf(nameLower));
        If (k>=0) then begin
          // Was deleted, rescue previous account number with name
          Result := FPreviousSafeBox.FDeletedNamesSincePreviousSafebox.GetTag(k);
        end;
      end;
      //
      while (j>=0) And (PSafeboxSnapshot(FPreviousSafeBox.FSnapshots[j])^.nBlockNumber>FPreviousSafeboxOriginBlock) do begin //  > ????
        Psnapshot := PSafeboxSnapshot(FPreviousSafeBox.FSnapshots[j]);
        // Start with added:
        If (Result>=0) then begin
          // I've found nameLower, search if was added (to undo)
          k := (Psnapshot^.namesAdded.IndexOf(nameLower));
          if (k>=0) then begin
            // Was addded, delete name
            Result := -1;
          end;
        end;
        // Then with deleted (in order to restore)
        If (Result<0) then begin
          // I've not found nameLower, search if was deleted
          k := (Psnapshot^.namesDeleted.IndexOf(nameLower));
          If (k>=0) then begin
            // Was deleted, rescue previous account number with name
            Result := Psnapshot^.namesDeleted.GetTag(k);
          end;
        end;
        dec(j); // Next previous snapshot
      end;
    end;
  end;
end;

procedure TPCSafeBox.SearchBlockWhenOnSeparatedChain(blockNumber: Cardinal; out blockAccount: TBlockAccount);
  Function WasUpdatedBeforeOrigin : Boolean;
  var j, maxUB : Integer;
  Begin
    // Is valid?
    maxUB := 0;
    for j:=Low(blockAccount.accounts) to High(blockAccount.accounts) do begin
      If blockAccount.accounts[j].updated_block>maxUB then maxUB := blockAccount.accounts[j].updated_block;
    end;
    Result := (maxUB <= FPreviousSafeboxOriginBlock);
  end;
var i,j : Integer;
  Pss : PSafeboxSnapshot;
begin
  If Not Assigned(FPreviousSafeBox) then Raise Exception.Create('ERROR DEV 20180320-1');
  // It's not stored on FBlockAccountsList
  // Search on my chain current chain
  If FModifiedBlocksSeparatedChain.Find(blockNumber,i) then begin
    blockAccount := FModifiedBlocksSeparatedChain.Get(i);
    Exit;
  end else begin
    // Has not changed on my chain, must search on PreviousSafebox chain AT OriginStartPos
    blockAccount := FPreviousSafeBox.Block(blockNumber);
    // Is valid?
    If WasUpdatedBeforeOrigin then Exit;
    //
    If FPreviousSafeBox.FModifiedBlocksPreviousState.Find(blockNumber,j) then begin
      blockAccount := FPreviousSafeBox.FModifiedBlocksPreviousState.Get(j);
      if WasUpdatedBeforeOrigin then Exit;
    end;

    // Must search on Previous when was updated!
    i := FPreviousSafeBox.FSnapshots.Count-1;
    while (i>=0) do begin
      Pss := FPreviousSafeBox.FSnapshots[i];
      If Pss.oldBlocks.Find(blockNumber,j) then begin
        blockAccount := Pss.oldBlocks.Get(j);
        If WasUpdatedBeforeOrigin then Exit;
      end;
      dec(i);
    end;
    Raise Exception.Create('ERROR DEV 20180318-1'); // Must find before!
  end;
end;

procedure TPCSafeBox.UpdateAccount(account_number : Cardinal; const newAccountInfo: TAccountInfo; const newName : TRawBytes; newType : Word; newBalance: UInt64; newN_operation: Cardinal;
  accountUpdateStyle : TAccountUpdateStyle; newUpdated_block, newPrevious_Updated_block : Cardinal);
Var iBlock : Cardinal;
  i,j,iAccount, iDeleted, iAdded : Integer;
  lastbalance : UInt64;
  blockAccount : TBlockAccount;
  Pblock : PBlockAccount;
begin
  iBlock := account_number DIV CT_AccountsPerBlock;
  iAccount := account_number MOD CT_AccountsPerBlock;

  blockAccount := Block(iBlock);
  FModifiedBlocksPreviousState.AddIfNotExists(blockAccount);
  If Assigned(FPreviousSafeBox) then begin
    Pblock := Nil;
  end else begin
    Pblock := FBlockAccountsList.Items[iBlock];
  end;

  if (NOT TAccountComp.EqualAccountKeys(blockAccount.accounts[iAccount].accountInfo.accountKey,newAccountInfo.accountKey)) then begin
    AccountKeyListRemoveAccount(blockAccount.accounts[iAccount].accountInfo.accountKey,[account_number]);
    AccountKeyListAddAccounts(newAccountInfo.accountKey,[account_number]);
  end;

  {$IFDEF useAccountKeyStorage}
  // Delete old references prior to change
  TAccountKeyStorage.KS.RemoveAccountKey(blockAccount.accounts[iAccount].accountInfo.accountKey);
  TAccountKeyStorage.KS.RemoveAccountKey(blockAccount.accounts[iAccount].accountInfo.new_publicKey);
  {$ENDIF}

  blockAccount.accounts[iAccount].accountInfo := newAccountInfo;
  blockAccount.accounts[iAccount].account_type:=newType;
  lastbalance := blockAccount.accounts[iAccount].balance;
  blockAccount.accounts[iAccount].balance := newBalance;
  blockAccount.accounts[iAccount].n_operation := newN_operation;

  If (accountUpdateStyle In [aus_rollback,aus_commiting_from_otherchain]) then begin
    // Directly update name and updated values
    blockAccount.accounts[iAccount].name:=newName;
    blockAccount.accounts[iAccount].updated_block:=newUpdated_block;
    blockAccount.accounts[iAccount].previous_updated_block:=newPrevious_Updated_block;
  end else begin
    // Name:
    If blockAccount.accounts[iAccount].name<>newName then begin
      If blockAccount.accounts[iAccount].name<>'' then begin

        i := FOrderedByName.IndexOf(blockAccount.accounts[iAccount].name);
        if i<0 then begin
          If (Not Assigned(FPreviousSafeBox)) then begin
            TLog.NewLog(ltError,ClassName,'ERROR DEV 20170606-1 Name "'+blockAccount.accounts[iAccount].name+'" not found for delete on account '+IntToStr(account_number));
          end;
        end else begin
          If (FOrderedByName.GetTag(i)<>account_number) then begin
            TLog.NewLog(ltError,ClassName,'ERROR DEV 20170606-3 Name "'+blockAccount.accounts[iAccount].name+'" not found for delete at suposed account '+IntToStr(account_number)+' found at '+IntToStr(FOrderedByName.GetTag(i)));
          end;
          FOrderedByName.Delete(i);
        end;

        iDeleted := FDeletedNamesSincePreviousSafebox.IndexOf(blockAccount.accounts[iAccount].name);
        iAdded := FAddedNamesSincePreviousSafebox.IndexOf(blockAccount.accounts[iAccount].name);

        If (iDeleted<0) then begin
          If (iAdded<0) then begin
            {$IFDEF HIGHLOG}TLog.NewLog(ltdebug,ClassName,Format('Deleted from PREVIOUS snapshot name:%s at account:%d',[blockAccount.accounts[iAccount].name,account_number]));{$ENDIF}
            FDeletedNamesSincePreviousSafebox.Add(blockAccount.accounts[iAccount].name,account_number); // Very important to store account_number in order to restore a snapshot!
          end else begin
            // Was added, so delete from added
            {$IFDEF HIGHLOG}TLog.NewLog(ltdebug,ClassName,Format('Deleted from current snapshot name:%s at account:%d',[blockAccount.accounts[iAccount].name,account_number]));{$ENDIF}
            FAddedNamesSincePreviousSafebox.Delete(iAdded);
          end;
        end else begin
          // Was deleted before, delete from added
          If (iAdded>=0) then begin
            FAddedNamesSincePreviousSafebox.Delete(iAdded);
          end;
        end;
      end;
      blockAccount.accounts[iAccount].name:=newName;
      If blockAccount.accounts[iAccount].name<>'' then begin
        i := FOrderedByName.IndexOf(blockAccount.accounts[iAccount].name);
        if i>=0 then TLog.NewLog(ltError,ClassName,'ERROR DEV 20170606-2 New Name "'+blockAccount.accounts[iAccount].name+'" for account '+IntToStr(account_number)+' found at account '+IntToStr(FOrderedByName.GetTag(i)));
        FOrderedByName.Add(blockAccount.accounts[iAccount].name,account_number);

        iDeleted := FDeletedNamesSincePreviousSafebox.IndexOf(blockAccount.accounts[iAccount].name);
        iAdded := FAddedNamesSincePreviousSafebox.IndexOf(blockAccount.accounts[iAccount].name);

        // Adding
        If (iDeleted>=0) Then begin
          if (FDeletedNamesSincePreviousSafebox.GetTag(iDeleted)=account_number) then begin
            // Is restoring to initial position, delete from deleted
            {$IFDEF HIGHLOG}TLog.NewLog(ltdebug,ClassName,Format('Adding equal to PREVIOUS (DELETING FROM DELETED) snapshot name:%s at account:%d',[blockAccount.accounts[iAccount].name,account_number]));{$ENDIF}
            FDeletedNamesSincePreviousSafebox.Delete(iDeleted);
            FAddedNamesSincePreviousSafebox.Remove(blockAccount.accounts[iAccount].name);
          end else begin
            // Was deleted, but now adding to a new account
            {$IFDEF HIGHLOG}TLog.NewLog(ltdebug,ClassName,Format('Adding again name:%s to new account account:%d',[blockAccount.accounts[iAccount].name,account_number]));{$ENDIF}
            FAddedNamesSincePreviousSafebox.Add(blockAccount.accounts[iAccount].name,account_number);
          end;
        end else begin
          // Was not deleted, Add it
          {$IFDEF HIGHLOG}TLog.NewLog(ltdebug,ClassName,Format('Adding first time at this snapshot name:%s at account:%d',[blockAccount.accounts[iAccount].name,account_number]));{$ENDIF}
          FAddedNamesSincePreviousSafebox.Add(blockAccount.accounts[iAccount].name,account_number);
        end;
      end;
    end;
    // Will update previous_updated_block only on first time/block
    If blockAccount.accounts[iAccount].updated_block<>BlocksCount then begin
      blockAccount.accounts[iAccount].previous_updated_block := blockAccount.accounts[iAccount].updated_block;
      blockAccount.accounts[iAccount].updated_block := BlocksCount;
    end;
  end;

  // Save new account values
  blockAccount.block_hash:=CalcBlockHash(blockAccount,FCurrentProtocol >= CT_PROTOCOL_2);
  FModifiedBlocksFinalState.Add(blockAccount);
  If Assigned(FPreviousSafeBox) then begin
    FModifiedBlocksSeparatedChain.Add(blockAccount);
  end;
  If (Assigned(Pblock)) then begin
    ToTMemAccount(blockAccount.accounts[iAccount],Pblock^.accounts[iAccount]);
    {$IFDEF uselowmem}
    TBaseType.To32Bytes(blockAccount.block_hash,Pblock^.block_hash);
    {$ELSE}
    Pblock^.block_hash := blockAccount.block_hash;
    {$ENDIF}
  end;
  // Update buffer block hash
  j := (length(blockAccount.block_hash)*(iBlock));  // j in 0,32,64...
  for i := 1 to length(blockAccount.block_hash) do begin  // i in 1..32
    FBufferBlocksHash[i+j] := AnsiChar(blockAccount.block_hash[i]);
  end;

  FTotalBalance := FTotalBalance - (Int64(lastbalance)-Int64(newBalance));
  FTotalFee := FTotalFee + (Int64(lastbalance)-Int64(newBalance));
end;

procedure TPCSafeBox.StartThreadSafe;
begin
  TPCThread.ProtectEnterCriticalSection(Self,FLock);
end;


end.
