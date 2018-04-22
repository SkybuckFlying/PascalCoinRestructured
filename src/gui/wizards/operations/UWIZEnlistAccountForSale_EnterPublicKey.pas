unit UWIZEnlistAccountForSale_EnterPublicKey;

{$mode delphi}
{$modeswitch nestedprocvars}

{ Copyright (c) 2018 by Ugochukwu Mmaduekwe

  Distributed under the MIT software license, see the accompanying file LICENSE
  or visit http://www.opensource.org/licenses/mit-license.php.
}

interface

uses
  Classes, SysUtils, FileUtil, Forms, Controls, Graphics, Dialogs, StdCtrls,
  ExtCtrls, Buttons, UWizard, UDataObjects, UWIZEnlistAccountForSale_EnterLockingBlock;

type

  { TWIZEnlistAccountForSale_EnterPublicKey }

  TWIZEnlistAccountForSale_EnterPublicKey = class(TWizardForm<TExecuteOperationsModel>)
    gbTransaction: TGroupBox;
    lblBlockLock: TLabel;
    lblPublicKey: TLabel;
    mmoPublicKey: TMemo;
  public
    procedure OnPresent; override;
    procedure OnNext; override;
    function Validate(out message: ansistring): boolean; override;
  end;


implementation

{$R *.lfm}

uses
  UAccounts;

{ TWIZEnlistAccountForSale_EnterPublicKey }

procedure TWIZEnlistAccountForSale_EnterPublicKey.OnPresent;
begin
  mmoPublicKey.SetFocus;
end;

procedure TWIZEnlistAccountForSale_EnterPublicKey.OnNext;
begin
   UpdatePath(ptInject, [TWIZEnlistAccountForSale_EnterLockingBlock]);
end;

function TWIZEnlistAccountForSale_EnterPublicKey.Validate(out message: ansistring): boolean;
var
  i: integer;
begin
  Result := True;

  if not TAccountComp.AccountKeyFromImport(Trim(mmoPublicKey.Lines.Text),
    Model.EnlistAccountForSale.NewOwnerPublicKey, message) then
  begin
    message := 'Public key: ' + message;
    Result := False;
    exit;

  end;

  for i := Low(Model.Account.SelectedAccounts) to High(Model.Account.SelectedAccounts) do
    if TAccountComp.EqualAccountKeys(Model.EnlistAccountForSale.NewOwnerPublicKey,
      Model.Account.SelectedAccounts[i].accountInfo.accountKey) then
    begin
      message := 'New public key for private sale is the same public key';
      Result := False;
      Exit;
    end;

end;

end.
