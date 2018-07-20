unit UBlockAccount;

interface

uses
  UOperationBlock, UConst, UAccount, URawBytes;

type
  TBlockAccount = Record
    blockchainInfo : TOperationBlock;
    accounts : Array[0..CT_AccountsPerBlock-1] of TAccount;
    block_hash: TRawBytes;   // Calculated on every block change (on create and on accounts updated)
    accumulatedWork : UInt64; // Accumulated work (previous + target) this value can be calculated.
  end;

var
  CT_BlockAccount_NUL : TBlockAccount;

implementation

initialization
  Initialize(CT_BlockAccount_NUL);

end.
