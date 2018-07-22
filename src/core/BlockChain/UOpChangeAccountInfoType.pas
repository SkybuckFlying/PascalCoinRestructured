unit UOpChangeAccountInfoType;

interface

type
  // Moved from UOpTransaction to here

  // Skybuck: dangerous to not put prefixes in place, could lead to wrong type usage, fixing it below in next line
//  TOpChangeAccountInfoType = (public_key,account_name,account_type,list_for_public_sale,list_for_private_sale,delist);
  TOpChangeAccountInfoType = (ait_public_key,ait_account_name,ait_account_type,ait_list_for_public_sale,ait_list_for_private_sale,delist);

  TOpChangeAccountInfoTypes = Set of TOpChangeAccountInfoType;

var
//  CT_TOpChangeAccountInfoType_Txt : Array[Low(TOpChangeAccountInfoType)..High(TOpChangeAccountInfoType)] of AnsiString = ('public_key','account_name','account_type','list_for_public_sale','list_for_private_sale','delist');
  // Skybuck: more efficient to write it this way.
  CT_TOpChangeAccountInfoType_Txt : Array[TOpChangeAccountInfoType] of AnsiString = ('public_key','account_name','account_type','list_for_public_sale','list_for_private_sale','delist');

implementation

end.
