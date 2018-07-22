unit UMultiOpReceiver;

interface

uses
  URawBytes;

type
  TMultiOpReceiver = Record
    Account : Cardinal;
    Amount : Int64;
    Payload : TRawBytes;
  end;
  TMultiOpReceivers = Array of TMultiOpReceiver;

var
  CT_TMultiOpReceiver_NUL : TMultiOpReceiver;

implementation

initialization
  Initialize(CT_TMultiOpReceiver_NUL);


end.
