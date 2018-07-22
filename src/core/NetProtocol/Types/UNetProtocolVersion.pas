unit UNetProtocolVersion;

interface

{
  Net Protocol:

  3 different types: Request,Response or Auto-send
  Request:   <Magic Net Identification (4b)><request  (2b)><operation (2b)><0x0000 (2b)><request_id(4b)><protocol info(4b)><data_length(4b)><request_data (data_length bytes)>
  Response:  <Magic Net Identification (4b)><response (2b)><operation (2b)><error_code (2b)><request_id(4b)><protocol info(4b)><data_length(4b)><response_data (data_length bytes)>
  Auto-send: <Magic Net Identification (4b)><autosend (2b)><operation (2b)><0x0000 (2b)><0x00000000 (4b)><protocol info(4b)><data_length(4b)><data (data_length bytes)>

  Min size: 4b+2b+2b+2b+4b+4b+4b = 22 bytes
  Max size: (depends on last 4 bytes) = 22..(2^32)-1
}


type
  TNetProtocolVersion = Record
    protocol_version,
    protocol_available : Word;
  end;

implementation

end.
