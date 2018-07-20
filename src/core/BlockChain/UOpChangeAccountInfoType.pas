unit UOpChangeAccountInfoType;

interface

type
  // Moved from UOpTransaction to here
  TOpChangeAccountInfoType = (public_key,account_name,account_type,list_for_public_sale,list_for_private_sale,delist);
  TOpChangeAccountInfoTypes = Set of TOpChangeAccountInfoType;

implementation

end.
