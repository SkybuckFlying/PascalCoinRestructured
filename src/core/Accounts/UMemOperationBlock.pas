unit UMemOperationBlock;

interface

uses
  UAccountKey, UDynRawBytes, U32Bytes;

{$include MemoryReductionSettings.inc}

{$IFDEF uselowmem}
type
  TMemOperationBlock = Record // TOperationBlock with less memory usage
    // block number is discarded (-4 bytes)
    {$IFDEF useAccountKeyStorage}
    account_keyKS: PAccountKey;
    {$ELSE}
    account_key: TDynRawBytes;
    {$ENDIF}
    reward: UInt64;
    fee: UInt64;
    protocol_version: Word;
    protocol_available: Word;
    timestamp: Cardinal;
    compact_target: Cardinal;
    nonce: Cardinal;
    block_payload : TDynRawBytes;
    initial_safe_box_hash: T32Bytes; // 32 direct bytes instead of use an AnsiString (-8 bytes)
    operations_hash: T32Bytes;       // 32 direct bytes instead of use an AnsiString (-8 bytes)
    proof_of_work: T32Bytes;         // 32 direct bytes instead of use an AnsiString (-8 bytes)
  end;
{$ENDIF}

implementation

end.
