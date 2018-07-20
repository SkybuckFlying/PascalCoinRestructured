unit UPBlockAccount;

interface

uses
  UMemBlockAccount, UBlockAccount;

{$include MemoryReductionSettings.inc}
type
{$IFDEF uselowmem}
  PBlockAccount = ^TMemBlockAccount;
{$ELSE}
  PBlockAccount = ^TBlockAccount;
{$ENDIF}

implementation

end.
