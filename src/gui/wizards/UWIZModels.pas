unit UWIZModels;


{$ifdef fpc}
  {$mode delphi}
{$endif}

interface

uses Classes, SysUtils, UWizard, UAccounts, UBlockChain, UWallet,
  UBaseTypes, Generics.Defaults;

type

  { TWIZAddKeyAction }

  TWIZAddKeyAction = (akaGenerateKey, akaImportPrivateKey, akaImportPublicKey);

  { TFRMAddKeyModel }

  TWIZAddKeyModel = class(TComponent)
  public
    Name: string;
    KeyText: string;
    Password: string;
    EncryptionTypeNID: word;
    Action: TWIZAddKeyAction;
  end;

  { TWIZOperationsModel }

  TWIZOperationsModel = class(TComponent)
  public
    type

    { TModelType }

    TModelType = (omtSendPasc, omtTransferAccount, omtChangeAccountPrivateKey,
      omtAddKey);

    { TPayloadEncryptionMode }

    TPayloadEncryptionMode = (akaEncryptWithSender, akaEncryptWithReceiver,
      akaEncryptWithPassword, akaNotEncrypt);

    { TOperationSigningMode }

    TOperationSigningMode = (akaPrimary, akaSecondary);

    { TSendPASCModel }

    TSendPASCModel = class(TComponent)
    public
      SelectedIndex: integer;
      SingleOperationFee, SingleAmountToSend: int64;
      HasPayload: boolean;
      PayloadContent, EncryptionPassword: string;
      EncodedPayload: TRawBytes;
      SignerAccount, DestinationAccount: TAccount;
      SelectedAccounts: TArray<TAccount>;
      PayloadEncryptionMode: TPayloadEncryptionMode;
      OperationSigningMode: TOperationSigningMode;
    end;

    { TTransferAccountModel }

    TTransferAccountModel = class(TComponent)
    public
      DefaultFee: int64;
      NewPublicKey, Payload, EncryptionPassword: string;
      SelectedIndex: integer;
      AccountKey: TAccountKey;
      EncodedPayload: TRawBytes;
      SignerAccount: TAccount;
      SelectedAccounts: TArray<TAccount>;
      PayloadEncryptionMode: TPayloadEncryptionMode;
    end;

    { TChangeAccountPrivateKeyModel }

    TChangeAccountPrivateKeyModel = class(TComponent)
    public
      DefaultFee: int64;
      NewPublicKey, Payload, EncryptionPassword: string;
      SelectedIndex, PrivateKeySelectedIndex: integer;
      NewWalletKey: TWalletKey;
      EncodedPayload: TRawBytes;
      SignerAccount: TAccount;
      SelectedAccounts: TArray<TAccount>;
      PayloadEncryptionMode: TPayloadEncryptionMode;
    end;

  private
    FModelType: TModelType;
    FSendModel: TSendPASCModel;
    FTransferAccountModel: TTransferAccountModel;
    FChangeAccountPrivateKeyModel: TChangeAccountPrivateKeyModel;
  public
    constructor Create(AOwner: TComponent; AType: TModelType); overload;
    property ModelType: TModelType read FModelType;
    property SendPASCModel: TSendPASCModel read FSendModel;
    property TransferAccountModel: TTransferAccountModel read FTransferAccountModel;
    property ChangeAccountPrivateKeyModel: TChangeAccountPrivateKeyModel
      read FChangeAccountPrivateKeyModel;
  end;

implementation

constructor TWIZOperationsModel.Create(AOwner: TComponent;
  AType: TWIZOperationsModel.TModelType);
begin
  inherited Create(AOwner);
  FModelType := AType;
  FSendModel := TSendPASCModel.Create(Self);
  FTransferAccountModel := TTransferAccountModel.Create(Self);
  FChangeAccountPrivateKeyModel := TChangeAccountPrivateKeyModel.Create(Self);
end;

end.
