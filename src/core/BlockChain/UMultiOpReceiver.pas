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

implementation

end.
