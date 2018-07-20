unit UNetProtocolConst;

interface

Const
  CT_MagicRequest = $0001;
  CT_MagicResponse = $0002;
  CT_MagicAutoSend = $0003;

  CT_NetOp_Hello                = $0001; // Sends my last operationblock + servers. Receive last operationblock + servers + same operationblock number of sender
  CT_NetOp_Error                = $0002;
  CT_NetOp_Message              = $0003;
  CT_NetOp_GetBlockHeaders      = $0005; // Sends from and to. Receive a number of OperationsBlock to check
  CT_NetOp_GetBlocks            = $0010;
  CT_NetOp_NewBlock             = $0011;
  CT_NetOp_AddOperations        = $0020;
  CT_NetOp_GetSafeBox           = $0021; // V2 Protocol: Allows to send/receive Safebox in chunk parts

  CT_NetOp_GetPendingOperations = $0030; // Obtain pending operations
  CT_NetOp_GetAccount           = $0031; // Obtain account info

  CT_NetOp_Reserved_Start       = $1000; // This will provide a reserved area
  CT_NetOp_Reserved_End         = $1FFF; // End of reserved area
  CT_NetOp_ERRORCODE_NOT_IMPLEMENTED = $00FF;// This will be error code returned when using Reserved area and Op is not implemented


  CT_NetError_InvalidProtocolVersion = $0001;
  CT_NetError_IPBlackListed = $0002;
  CT_NetError_InvalidDataBufferInfo = $0010;
  CT_NetError_InternalServerError = $0011;
  CT_NetError_InvalidNewAccount = $0012;
  CT_NetError_SafeboxNotFound = $00020;

  CT_LAST_CONNECTION_BY_SERVER_MAX_MINUTES = 60*60*3;
  CT_LAST_CONNECTION_MAX_MINUTES = 60*60;
  CT_MAX_NODESERVERS_ON_HELLO = 10;
  CT_MIN_NODESERVERS_BUFFER = 50;
  CT_MAX_NODESERVERS_BUFFER = 300;


implementation

end.
