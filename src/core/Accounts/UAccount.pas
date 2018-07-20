unit UAccount;

interface

uses
  UAccountInfo, URawBytes;

type
  TAccount = Record
    account: Cardinal;        // FIXED value. Account number
    accountInfo : TAccountInfo;
    balance: UInt64;          // Balance, always >= 0
    updated_block: Cardinal;  // Number of block where was updated
    n_operation: Cardinal;    // count number of owner operations (when receive, this is not updated)
    name : TRawBytes;         // Protocol 2. Unique name
    account_type : Word;      // Protocol 2. Layer 2 use case
    previous_updated_block : Cardinal; // New Build 1.0.8 -> Only used to store this info to storage. It helps App to search when an account was updated. NOT USED FOR HASH CALCULATIONS!
  End;
  PAccount = ^TAccount;

var
  CT_Account_NUL : TAccount;

implementation

initialization
  Initialize(CT_Account_NUL);

end.
