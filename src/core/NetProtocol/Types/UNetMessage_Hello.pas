unit UNetMessage_Hello;

interface

uses
  UOperationBlock, UNodeServerAddress;

type
  TNetMessage_Hello = Record
     last_operation : TOperationBlock;
     servers_address : Array of TNodeServerAddress;
  end;

implementation

end.
