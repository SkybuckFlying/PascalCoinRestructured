unit UNetHeaderData;

interface

uses
  UNetTransferType, UNetProtocolVersion;

type
  TNetHeaderData = Record
    header_type : TNetTransferType;
    protocol : TNetProtocolVersion;
    operation : Word;
    request_id : Cardinal;
    buffer_data_length : Cardinal;
    //
    is_error : Boolean;
    error_code : Integer;
    error_text : AnsiString;
  end;

var
  CT_NetHeaderData : TNetHeaderData;

implementation


initialization
  Initialize(CT_NetHeaderData);

end.
