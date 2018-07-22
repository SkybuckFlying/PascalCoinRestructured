unit UNetTransferType;

interface

type
  TNetTransferType = (ntp_unknown, ntp_request, ntp_response, ntp_autosend);

var
  CT_NetTransferType : Array[TNetTransferType] of AnsiString = ('Unknown','Request','Response','Autosend');

implementation

end.
