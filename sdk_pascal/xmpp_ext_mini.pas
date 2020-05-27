unit xmpp_ext_mini;

//xmpp mini 相对于标准 xmpp 进行的扩展//主要是消息体和一些服务器的寻址而已

interface

//图片信息//扩展
function xmpp_mini_EncodeMsg_Image(url:string):string;

implementation

//这里的 s 是键值对的多行文本，如
//url=http://123.com
//
function xmpp_mini_Encode(s:string):string;
begin
  //
  Result := '[xmpp_mini]' + s + '[xmpp_mini_end]';
end;


//图片信息//扩展
function xmpp_mini_EncodeMsg_Image(url:string):string;
var
  s:string;
begin
  //
  s := 'desc=' + '图片地址扩展信息' + #13#10;
  s := s + 'type=' + 'image' + #13#10;
  s := s + 'image_src=' + url + #13#10;

  Result := xmpp_mini_Encode(s);
end;  


end.
