unit UMultiOpSender;

interface

uses
  URawBytes, UCrypto;

type
  // MultiOp... will allow a MultiOperation
  TMultiOpSender = Record
    Account : Cardinal;
    Amount : Int64;
    N_Operation : Cardinal;
    Payload : TRawBytes;
    Signature : TECDSA_SIG;
  end;
  TMultiOpSenders = Array of TMultiOpSender;

var
  CT_TMultiOpSender_NUL : TMultiOpSender;

implementation

initialization
  Initialize(CT_TMultiOpSender_NUL);


end.
