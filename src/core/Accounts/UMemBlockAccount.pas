unit UMemBlockAccount;

interface

uses
  UMemOperationBlock, UConst, UMemAccount, U32Bytes, UBlockAccount;

{$include MemoryReductionSettings.inc}

{$IFDEF uselowmem}
type
  TMemBlockAccount = Record // TBlockAccount with less memory usage
    blockchainInfo : TMemOperationBlock;
    accounts : Array[0..CT_AccountsPerBlock-1] of TMemAccount;
    block_hash: T32Bytes;     // 32 direct bytes instead of use an AnsiString (-8 bytes)
    accumulatedWork : UInt64;
  end;
{$ELSE}
Type
  TMemBlockAccount = TBlockAccount;
{$ENDIF}

procedure ToTMemBlockAccount(const source : TBlockAccount; var dest : TMemBlockAccount);
procedure ToTBlockAccount(const source : TMemBlockAccount; block_number : Cardinal; var dest : TBlockAccount);

implementation

uses
  URawBytes, UAccountKeyStorage, UBaseType;

procedure ToTMemBlockAccount(const source : TBlockAccount; var dest : TMemBlockAccount);
{$IFDEF uselowmem}
var i : Integer;
var raw : TRawBytes;
{$ENDIF}
Begin
  {$IFDEF uselowmem}
  {$IFDEF useAccountKeyStorage}
  dest.blockchainInfo.account_keyKS:=TAccountKeyStorage.KS.AddAccountKey(source.blockchainInfo.account_key);
  {$ELSE}
  TAccountComp.AccountKey2RawString(source.blockchainInfo.account_key,raw);
  TBaseType.To256RawBytes(raw,dest.blockchainInfo.account_key);
  {$ENDIF}
  dest.blockchainInfo.reward:=source.blockchainInfo.reward;
  dest.blockchainInfo.fee:=source.blockchainInfo.fee;
  dest.blockchainInfo.protocol_version:=source.blockchainInfo.protocol_version;
  dest.blockchainInfo.protocol_available:=source.blockchainInfo.protocol_available;
  dest.blockchainInfo.timestamp:=source.blockchainInfo.timestamp;
  dest.blockchainInfo.compact_target:=source.blockchainInfo.compact_target;
  dest.blockchainInfo.nonce:=source.blockchainInfo.nonce;
  TBaseType.To256RawBytes(source.blockchainInfo.block_payload,dest.blockchainInfo.block_payload);
  TBaseType.To32Bytes(source.blockchainInfo.initial_safe_box_hash,dest.blockchainInfo.initial_safe_box_hash);
  TBaseType.To32Bytes(source.blockchainInfo.operations_hash,dest.blockchainInfo.operations_hash);
  TBaseType.To32Bytes(source.blockchainInfo.proof_of_work,dest.blockchainInfo.proof_of_work);

  for i := Low(source.accounts) to High(source.accounts) do begin
    ToTMemAccount(source.accounts[i],dest.accounts[i]);
  end;
  TBaseType.To32Bytes(source.block_hash,dest.block_hash);
  dest.accumulatedWork := source.accumulatedWork;
  {$ELSE}
  dest := source;
  {$ENDIF}
end;

procedure ToTBlockAccount(const source : TMemBlockAccount; block_number : Cardinal; var dest : TBlockAccount);
{$IFDEF uselowmem}
var i : Integer;
  raw : TRawBytes;
{$ENDIF}
begin
  {$IFDEF uselowmem}
  dest.blockchainInfo.block:=block_number;
  {$IFDEF useAccountKeyStorage}
  dest.blockchainInfo.account_key := source.blockchainInfo.account_keyKS^;
  {$ELSE}
  TBaseType.ToRawBytes(source.blockchainInfo.account_key,raw);
  TAccountComp.RawString2Accountkey(raw,dest.blockchainInfo.account_key);
  {$ENDIF}
  dest.blockchainInfo.reward:=source.blockchainInfo.reward;
  dest.blockchainInfo.fee:=source.blockchainInfo.fee;
  dest.blockchainInfo.protocol_version:=source.blockchainInfo.protocol_version;
  dest.blockchainInfo.protocol_available:=source.blockchainInfo.protocol_available;
  dest.blockchainInfo.timestamp:=source.blockchainInfo.timestamp;
  dest.blockchainInfo.compact_target:=source.blockchainInfo.compact_target;
  dest.blockchainInfo.nonce:=source.blockchainInfo.nonce;
  TBaseType.ToRawBytes(source.blockchainInfo.block_payload,dest.blockchainInfo.block_payload);
  TBaseType.ToRawBytes(source.blockchainInfo.initial_safe_box_hash,dest.blockchainInfo.initial_safe_box_hash);
  TBaseType.ToRawBytes(source.blockchainInfo.operations_hash,dest.blockchainInfo.operations_hash);
  TBaseType.ToRawBytes(source.blockchainInfo.proof_of_work,dest.blockchainInfo.proof_of_work);

  for i := Low(source.accounts) to High(source.accounts) do begin
    ToTAccount(source.accounts[i],(block_number*CT_AccountsPerBlock)+i,dest.accounts[i]);
  end;
  TBaseType.ToRawBytes(source.block_hash,dest.block_hash);
  dest.accumulatedWork := source.accumulatedWork;
  {$ELSE}
  dest := source;
  {$ENDIF}
end;



end.
