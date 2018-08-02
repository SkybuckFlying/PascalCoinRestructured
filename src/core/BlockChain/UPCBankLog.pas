unit UPCBankLog;

interface

uses
  {UPascalCoinBank,} UPCOperationsComp, ULog;

type
  // Skybuck: leads to circular reference, replacing with TObject
//  TPCBankLog = procedure(sender: TPCBank; Operations: TPCOperationsComp; Logtype: TLogType ; Logtxt: AnsiString) of object;
  TPCBankLog = procedure(sender: TObject; Operations: TPCOperationsComp; Logtype: TLogType ; Logtxt: AnsiString) of object;

implementation

end.
