unit UOperationResume;

interface

uses
  UAccountKey, URawBytes, UMultiOpSender, UMultiOpReceiver, UMultiOpChangeInfo;

type
  TOperationResume = Record
    valid : Boolean;
    Block : Cardinal;
    NOpInsideBlock : Integer;
    OpType : Word;
    OpSubtype : Word;
    time : Cardinal;
    AffectedAccount : Cardinal;
    SignerAccount : Int64; // Is the account that executes this operation
    n_operation : Cardinal;
    DestAccount : Int64;   //
    SellerAccount : Int64; // Protocol 2 - only used when is a pay to transaction
    newKey : TAccountKey;
    OperationTxt : AnsiString;
    Amount : Int64;
    Fee : Int64;
    Balance : Int64;
    OriginalPayload : TRawBytes;
    PrintablePayload : AnsiString;
    OperationHash : TRawBytes;
    OperationHash_OLD : TRawBytes; // Will include old oeration hash value
    errors : AnsiString;
    // New on V3 for PIP-0017
    isMultiOperation : Boolean;
    Senders : TMultiOpSenders;
    Receivers : TMultiOpReceivers;
    Changers : TMultiOpChangesInfo;
  end;

var
  CT_TOperationResume_NUL : TOperationResume; // initialized in initialization section

implementation

initialization

  Initialize(CT_TOperationResume_NUL);
  with CT_TOperationResume_NUL do
  begin
    NOpInsideBlock:=-1;
    SignerAccount:=-1;
    DestAccount:=-1;
    SellerAccount:=-1;
  end;

end.
