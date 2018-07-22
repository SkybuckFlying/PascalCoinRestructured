unit UPCOperationClass;

interface

uses
  UPCOperation;

type
  TPCOperationClass = Class of TPCOperation;

var
  _OperationsClass: Array of TPCOperationClass;

Procedure RegisterOperationsClass;

implementation

uses
  UPCOperationsComp, UOpTransaction, UTxMultiOperation;

{
  UOpChangeKey,
  UOpRecoverFounds,
  UOpListAccountForSale,
  UDelistAccountForSale,
  UOpBuyAccount,
  UOpChangeKeySigned,
  UOpChangeAccountInfo,
  UOpMultiOperation;
}

Procedure RegisterOperationsClass;
Begin
  TPCOperationsComp.RegisterOperationClass(TOpTransaction);
  TPCOperationsComp.RegisterOperationClass(TOpChangeKey);
  TPCOperationsComp.RegisterOperationClass(TOpRecoverFounds);
  TPCOperationsComp.RegisterOperationClass(TOpListAccountForSale);
  TPCOperationsComp.RegisterOperationClass(TOpDelistAccountForSale);
  TPCOperationsComp.RegisterOperationClass(TOpBuyAccount);
  TPCOperationsComp.RegisterOperationClass(TOpChangeKeySigned);
  TPCOperationsComp.RegisterOperationClass(TOpChangeAccountInfo);
  TPCOperationsComp.RegisterOperationClass(TOpMultiOperation);
End;

initialization

  SetLength(_OperationsClass, 0);
  RegisterOperationsClass;

end.
