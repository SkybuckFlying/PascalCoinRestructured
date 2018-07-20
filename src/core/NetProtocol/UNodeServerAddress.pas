unit UNodeServerAddress;

interface

type
  TNodeServerAddress = Record
    ip : AnsiString;
    port : Word;
    last_connection : Cardinal;
    last_connection_by_server : Cardinal;
    last_connection_by_me : Cardinal;
    //
    netConnection : TNetConnection;
    its_myself : Boolean;
    last_attempt_to_connect : TDateTime;
    total_failed_attemps_to_connect : Integer;
    is_blacklisted : Boolean; // Build 1.4.4
    BlackListText : String;
  end;
  TNodeServerAddressArray = Array of TNodeServerAddress;
  PNodeServerAddress = ^TNodeServerAddress;

var
  CT_TNodeServerAddress_NUL : TNodeServerAddress;

implementation

initialization
  Initialize(CT_TNodeServerAddress_NUL)

end.
