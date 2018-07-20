unit UPCSafeBoxHeader;

interface

uses
  URawBytes;

type
  TPCSafeBoxHeader = Record
    protocol : Word;
    startBlock,
    endBlock,
    blocksCount : Cardinal;
    safeBoxHash : TRawBytes;
  end;

var
  CT_PCSafeBoxHeader_NUL : TPCSafeBoxHeader;

implementation

initialization
  Initialize(CT_PCSafeBoxHeader_NUL);


end.
