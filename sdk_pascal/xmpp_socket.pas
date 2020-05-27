unit xmpp_socket;

//xmpp 通讯层

interface

uses
  Windows, Messages, SysUtils, Variants, Classes, Graphics, Controls, Forms,
  Dialogs, StdCtrls, IdBaseComponent, IdComponent, IdTCPConnection,
  EncdDecd,
  IdTCPClient, Sockets, WinSock;




function xmpp_login_string(user, pass:string): string;
//忽略大小写
function FindStr(subs, s:string):Boolean;

//数据收到的事件
//- (void)on_recv:(NSString *)s  //参考 ios 版本
procedure xmpp_on_recv();

//处理完一个节点的数据后要将它清空出缓冲区，其实 xmpp 消息一般都很小，简单点直接清空也是可以的
procedure xmpp_clear_one_node();

//以节点字符串为分隔去掉前面处理过的内容
procedure xmpp_clear_one_node_END_STRING(node_end_string:string);

//重连时要清空和重置数据
procedure xmpp_reset();

//取域名
function GetHost(user_name:string):string;

//对于 openfire 服务器来说，认证时的用户名不能带域名//但对于其他的服务器来说最好还是带上
function GetUser_NotHost(user_name:string):string;

//同 ios 版本的函数名
function xmpp_send_string(s:string):Integer;

//发送消息时的字符串
function xmpp_string_message(from, _to, msg:string): string;


//简单的把单个引号变成双引号
function xmpp_format(s:string):string;

//客户端发送给服务器的心跳包
function xmpp_ping_client2server_string(user:string): string;


//其实直接参考 ios 版本的 就可以了，简单有效,在 ViewController_login.m 和 uThreadLogin.m 中

var
  gSo:TSocket = -1;
  gXmppHost:string = ''; //xmpp 协议中的域名，例如 newbt.net
  gXmppBindId:string = ''; //xmpp 协议中的绑定 id
  gXmppFullJid:string = ''; //xmpp 协议中的绑定后返回的全 jid 名称
  //gClient:TNBClient;
  gAtConnect:Boolean = False; //是否是在连接
  gIsConnect:Boolean = False;
  gRecvBuf:string = ''; //接收缓冲区

  gRecvHaveOnePack:Boolean = False; //上次数据包中是否有一个完整的数据节点，如果有的话就先不忙再次读取，应该再尝试看看是否还能解析出
  //下一个包，因为有可能服务器一次发送了两个包过来//如果如处理一个的话就会发现下次读取时会得到这次的第二个包
  //例如对方发送两条消息时，客户端会出现怪异现象

  

  xmpp_atLogin:Boolean = False; //代替 xmppStream.atLogin
  xmpp_isLoginOk:Boolean = False;
  xmpp_atBind:Boolean = False;
  xmpp_xmpp_jid:string = '';
  xmpp_atSession:Boolean = False;

implementation

uses
  form_log, //只是为了 addlog 函数而已，可以用别的处定义的简单代替，这些都是在主线程中调用的不用考虑张志和安全问题
  socketplus, functions, xmpp_xml;


var
  xmpp_xmpp_id:Integer = 1; //累加用的，并没有太多作用  

//重连时要清空和重置数据
procedure xmpp_reset();
begin

  gSo:= -1;
  gXmppHost:= ''; //xmpp 协议中的域名，例如 newbt.net
  gXmppBindId:= ''; //xmpp 协议中的绑定 id
  gXmppFullJid:= ''; //xmpp 协议中的绑定后返回的全 jid 名称
  //gClient:TNBClient;
  gAtConnect:= False; //是否是在连接
  gIsConnect:= False;
  gRecvBuf:= ''; //接收缓冲区

  xmpp_atLogin:= False; //代替 xmppStream.atLogin
  xmpp_isLoginOk:=False; //是否登录成功
end;  

function base64encode(s:string):string;
begin
  Result := EncdDecd.EncodeString(s);

  Result := StringReplace(Result, #13#10, '', [rfIgnoreCase, rfReplaceAll]);

end;

function base64decode(s:string):string;
begin
  Result := EncdDecd.DecodeString(s);
end;

//取域名
function GetHost(user_name:string):string;
begin
  Result := get_value(user_name, '@', '');

  //有资源 id 的话要还删除掉
  if FindStr('/', Result) then
  begin
    Result := get_value(Result, '', '/');
  end;  

end;

//对于 openfire 服务器来说，认证时的用户名不能带域名//但对于其他的服务器来说最好还是带上
//好像现在带域名也是可以的
function GetUser_NotHost(user_name:string):string;
begin
  //Result := get_value(user_name, '@', '');
  Result := get_value(user_name, '', '@');

  //有资源 id 的话要还删除掉
  if FindStr('/', Result) then
  begin
    Result := get_value(Result, '', '/');
  end;  

end;


//登录时发出的字符串
function xmpp_login_string(user, pass:string): string;
begin
  //<auth mechanism="PLAIN" xmlns="urn:ietf:params:xml:ns:xmpp-sasl">c3lzYWRtaW4Ac3lzYWRtaW4AMTIz</auth>
  //   Implements the PLAIN server-side mechanism. (RFC 4616)
  //client ----- {authzid, authcid, password} -----> server  //反正这里用 '用户名'0'用户名'0'密码'  就登录成功了,好象是用 #0 来分隔的字符
////  Memo2.Lines.Add('<auth mechanism="PLAIN" xmlns="urn:ietf:params:xml:ns:xmpp-sasl">' + base64encode('t1'#0't1'#0'1') + '</auth>');

  Result := '<auth mechanism="PLAIN" xmlns="urn:ietf:params:xml:ns:xmpp-sasl">' + base64encode(user + #0 + user + #0 + pass) + '</auth>';
  //奇怪，对于 ejabberd-19.08-windows 要去掉第一个 authzid
  Result := '<auth mechanism="PLAIN" xmlns="urn:ietf:params:xml:ns:xmpp-sasl">' + base64encode('' + #0 + user + #0 + pass) + '</auth>';

end;

//客户端发送给服务器的心跳包
function xmpp_ping_client2server_string(user:string):string;
var
  s_id:string;
begin
  //<iq from='juliet@capulet.lit/balcony' to='capulet.lit' id='c2s1' type='get'>
  //  <ping xmlns='urn:xmpp:ping'/>
  //</iq>

  xmpp_xmpp_id := xmpp_xmpp_id + 1;
  s_id := IntToStr(xmpp_xmpp_id);

  //gXmppFullJid 目前其实是和 xmpp_xmpp_jid 相同的

  Result := '<iq from="' + xmpp_xmpp_jid + '" to="' + GetHost(xmpp_xmpp_jid)  + '" id="' + s_id + '" type="get">' +
    '<ping xmlns="urn:xmpp:ping"/>' +
    '</iq>' +
    '';

  //--------------------------------------------------------
  //注意，这时候的回应是有可能和其他的回应冲突的，所以只有和客户端 id 相同的才是这个消息的回应
  //<iq from='capulet.lit' to='juliet@capulet.lit/balcony' id='c2s1' type='result'/>

  //按协议不支持应该回应以下内容，不过实际上不一定，所以不能依赖这个
  //<iq from='capulet.lit' to='juliet@capulet.lit/balcony' id='c2s1' type='error'>
  //  <ping xmlns='urn:xmpp:ping'/>
  //  <error type='cancel'>
  //    <service-unavailable xmlns='urn:ietf:params:xml:ns:xmpp-stanzas'/>
  //  </error>
  //</iq>

end;

//发送消息时的字符串
function xmpp_string_message(from, _to, msg:string): string;
begin
  //<auth mechanism="PLAIN" xmlns="urn:ietf:params:xml:ns:xmpp-sasl">c3lzYWRtaW4Ac3lzYWRtaW4AMTIz</auth>
  //   Implements the PLAIN server-side mechanism. (RFC 4616)
  //client ----- {authzid, authcid, password} -----> server  //反正这里用 '用户名'0'用户名'0'密码'  就登录成功了,好象是用 #0 来分隔的字符
////  Memo2.Lines.Add('<auth mechanism="PLAIN" xmlns="urn:ietf:params:xml:ns:xmpp-sasl">' + base64encode('t1'#0't1'#0'1') + '</auth>');

  Result := '<auth mechanism="PLAIN" xmlns="urn:ietf:params:xml:ns:xmpp-sasl">' + base64encode(from + #0 + from + #0 + from) + '</auth>';
  //奇怪，对于 ejabberd-19.08-windows 要去掉第一个 authzid
  Result := '<auth mechanism="PLAIN" xmlns="urn:ietf:params:xml:ns:xmpp-sasl">' + base64encode('' + #0 + from + #0 + from) + '</auth>';

  //<message to='ccc@newbt.net' from="ccc2@newbt.net/Spark" type='chat'><body>hhhhhhhhhhh</body><x xmlns="jabber:x:event"><offline/><composing/></x><active xmlns='http://jabber.org/protocol/chatstates'/></message>
  Result := '<message to="' + _to + '" from="' + from + '/xmppmini" type="chat"><body>' +
  msg +
  '</body><x xmlns="jabber:x:event"><offline/><composing/></x><active xmlns="http://jabber.org/protocol/chatstates"/></message>';

end;


//简单的把单个引号变成双引号
function xmpp_format(s:string):string;
begin
  s := StringReplace(s, #39, '"', [rfReplaceAll]);

  Result := s;
end;  


//忽略大小写
function FindStr(subs, s:string):Boolean;
begin
  s := LowerCase(s);         //其实从 xmpp 协议的角度来说不转也是可以是，不过为了算法通用还是转一下忽略大小写比较好
  subs := LowerCase(subs);

  Result := Pos(subs, s)>0;
end;

//处理完一个节点的数据后要将它清空出缓冲区，其实 xmpp 消息一般都很小，简单点直接清空也是可以的
procedure xmpp_clear_one_node();
begin
  gRecvBuf := '';
end;

//以节点字符串为分隔去掉前面处理过的内容
//xmpp_clear_one_node_END_STRING('message>');
//function xmpp_clear_one_node(s:string):string;
//其实对于 xmpp 来说一般只用在对方连续快速发送多个消息的 message 节点中，其他的时候直接清空也是可以的
procedure xmpp_clear_one_node_END_STRING(node_end_string:string);
var
  s:string;
begin
  s := gRecvBuf;

  s := get_value(s, node_end_string, '');

  gRecvBuf := s;
end;


//同 ios 版本的函数名
procedure clearRecvBuf;
begin
  xmpp_clear_one_node()
end;

//同 ios 版本的函数名
function xmpp_send_string(s:string):Integer;
begin
  AddLog('客户端发送:' + s);
  //Result := socketplus.SendBuf(gSo, s);
  Result := socketplus.SendBuf_TimeOut(gSo, s, 5); //5 秒就足够发送 260k 的 Form.pas 了
end;


//数据收到的事件
//- (void)on_recv:(NSString *)s  //参考 ios 版本
procedure xmpp_on_recv();
var
  s:string;
  first_login:string;
  resource_bind:string;
  s_id:string;
  ss:string;
  s_presence:string;
begin
  //这里直接使用 gRecvBuf 所以不需要传递参数了

  s := gRecvBuf;

  //</mechanism> 中是认证标识
  //if ("</mechanism>")
  if FindStr('</mechanism>', s) then
  begin
    //NSLog(@"发现认证标识");
    AddLog('发现认证标识') ;
  end;

  //登录失败服务器回应是 '<failure xmlns="urn:ietf:params:xml:ns:xmpp-sasl"><not-authorized></not-authorized></failure>'
  //成功则是 '<success'

  //登录成功后，需要再发送一次第一句的流开头字符串，这时候 xmpp 服务器的回应就是不同的了
  if FindStr('<failure', s) then
  begin
    //NSLog(@"发现认证标识");
    AddLog('登录失败') ;
  end;


    //--------------------------------------
    //正在登录中
    if (xmpp_atLogin = true) then begin
        
        if FindStr('<success', s ) then begin
            
            AddLog('登录成功');
            clearRecvBuf(); ////清空接收缓存
            
            xmpp_isLoginOk := true;
            
            //NSString * first_login = @"<stream:stream to=\"117.169.20.236\" xmlns=\"jabber:client\" xmlns:stream=\"http://etherx.jabber.org/streams\" version=\"1.0\">";

            //openfire 可以，ejabberd-19.08-windows 不行
            //first_login := '<stream:stream to="127.0.0.1" xmlns="jabber:client" xmlns:stream="http://etherx.jabber.org/stream\" version="1.0">';
            //原因是错了一个字符，因为 ejabberd-19.08-windows 很严格，而且域名也是要正确的
            first_login := '<stream:stream to="' + gXmppHost+ '" xmlns="jabber:client" xmlns:stream="http://etherx.jabber.org/streams" version="1.0">';

//ok  ejabberd-19.08-windows 也行
//      socketplus.SendBuf(gSo, '<stream:stream xmlns="jabber:client" xmlns:stream="http://etherx.jabber.org/streams" version="1.0" to="'+
//      gXmppHost +
//      '">'); //这句才是关键


            xmpp_atBind := true;
            //登录成功后要发第一个请求
            //[self send_string: first_login];
            //socketplus.SendBuf(gSo, first_login);
            xmpp_send_string(first_login);
            //对方应该回应什么? 暂时认为是 "<bind" 吧,表示服务器登录成功后会让我们 bind
        end;
    
    end;

    //2019//下面的 bind, session, presence 三个命令是兼容 openfire 服务器时必须要加上的，对于 xmppmini 服务器并不是必须的
    //以后的 openfire 服务器也有可能还需要更多的兼容命令，目前为兼容 openfire_4_1_4

    //--------------------------------------
    //登录成功后再发送 stream:stream 后就可以等待进行 bind 了
    //####server响应并返回支持的features
    //####client请求resource bind
    //参考 https://blog.csdn.net/lixiaowei16/article/details/48573839
    
    //正在 bind 中,有多个判断及命令发送出去
    if (xmpp_atBind = true) then begin

        //对于 ejabberd-19.08-windows  'stream:stream xmlns:stream' 并不一定是要一起的
        //if (FindStr('stream:stream xmlns:stream', s)) and (FindStr('urn:ietf:params:xml:ns:xmpp-bind', s) ) then begin //服务器确认有 bind 功能
        if (FindStr('stream:stream', s)) and (FindStr('xmlns:stream', s)) and (FindStr('urn:ietf:params:xml:ns:xmpp-bind', s) ) then begin //服务器确认有 bind 功能

            AddLog('服务器确认有 bind 功能');
            clearRecvBuf(); ////清空接收缓存
            
            //self.isLoginOk = true;
            
            //####client请求resource bind
            //NSString * first_login = @"<stream:stream to=\"117.169.20.236\" xmlns=\"jabber:client\" xmlns:stream=\"http://etherx.jabber.org/streams\" version=\"1.0\">";
            resource_bind := '<stream:stream to="127.0.0.1" xmlns="jabber:client" xmlns:stream="http://etherx.jabber.org/streams" version="1.0">';
            
            xmpp_xmpp_id := xmpp_xmpp_id + 1;
            s_id := IntToStr(xmpp_xmpp_id);
            
            resource_bind :=
                             //@"<iq type=\"set\" id=\"bind_1\">", //这里的 id 在 spark 中一直累加,所以并不用多理会,一直累加就可以了
                             '<iq type="set" id="' +  s_id + '">' + //这里的 id 在 spark 中一直累加,所以并不用多理会,一直累加就可以了
                             '<bind xmlns="urn:ietf:params:xml:ns:xmpp-bind">' +
                             //@"<resource>Psi+</resource>",
                             '<resource>ios</resource>' +
                             '</bind>' +
                             '</iq>' +
                             '';
            
            xmpp_atBind := true;
            //登录成功后要发第一个请求
            AddLog('resource_bind: ' + resource_bind);
            xmpp_send_string(resource_bind);
            //对方应该回应什么? 暂时认为是 "<bind" 吧,表示服务器登录成功后会让我们 bind
        end;//if 2
        
        //bind 请求的回应
        if (FindStr('result' ,s))and(FindStr('urn:ietf:params:xml:ns:xmpp-bind', s)) then begin

            AddLog('服务器回应 bind 请求');
            clearRecvBuf(); ////清空接收缓存
            
            //<jid>t1@127.0.0.1/ios</jid></bind></iq>
            if (FindStr('</bind></iq>', s)) then begin //成功,可以取服务器分配的 jid 了

                //self.xmpp_jid = [Functions get_value:s b_sp1:@"<jid>" e_sp1:@"</jid></bind></iq>"];
                ////xmpp_xmpp_jid = [Functions get_value:s b_sp1:@"<jid>" e_sp1:@"</jid></bind></iq>"];
                xmpp_xmpp_jid := get_value(s, '<jid>',  '</jid></bind></iq>');
                AddLog('xmpp_jid:' + xmpp_xmpp_jid);

                //gXmppFullJid 目前其实是和 xmpp_xmpp_jid 相同的
                gXmppFullJid := Trim(xmpp_xmpp_jid);

                //-----------------------
                //bind 成功后就可以 client发起session //不过发起 session 的目的是什么? 似乎后面并没有用到 session 的东西
                xmpp_atBind := false;
                xmpp_atSession := true;
                
                xmpp_xmpp_id := xmpp_xmpp_id + 1;
                s_id := IntToStr(xmpp_xmpp_id);
                
                //<iq id="48mz5-1" type="set"><session xmlns="urn:ietf:params:xml:ns:xmpp-session"/>
                ss :=
                                '<iq id="' +
                                 s_id +
                                '" type="set"><session xmlns="urn:ietf:params:xml:ns:xmpp-session"/>' +
                                '</iq>' +
                                '';
//ok
//ss := '<iq id="82imm-1" type="set">' +
//'<session xmlns="urn:ietf:params:xml:ns:xmpp-session"/>' +
//'</iq>' ;

                
                AddLog('ss:' + ss);
                xmpp_send_string( ss);
            end;//if 3

        end;//if 2
        
    end;//if 1

    //--------------------------------------
    //正在 atSession 中
    if (xmpp_atSession = true) then begin

        //奇怪，没有这个上线消息 openfire 是不会发送对话消息过来的
        //(*
        if (FindStr('result', s)) then begin
            
            AddLog('服务器回应 session 请求');
            clearRecvBuf(); //清空接收缓存
            
            //self.isLoginOk = true;
            
            //<presence id="48mz5-10"><status>在线</status><priority>1</priority></presence>
            
            xmpp_xmpp_id := xmpp_xmpp_id + 1;
            s_id := IntToStr(xmpp_xmpp_id);
            
            //这个是 spark 的回应,psi 的回应其实并没有中文
            //openfire 可以，但 ejabberd-19.08-windows 一定要转换成 utf8 ，所以还不如用英文状态好了
            //具体要求见后面注释部分的解释
            //s_presence := '<presence id="' + s_id + '"><status>在线</status><priority>1</priority></presence>'; //no ejb...
            ////s_presence := '<presence id="' + s_id + '"><status>' + AnsiToUtf8('在线') + '</status><priority>1</priority></presence>'; //ok ejb..
            s_presence := '<presence id="' + s_id + '"><status>' + AnsiToUtf8('online') + '</status><priority>1</priority></presence>'; //ok ejb..

            //self.atBind = true;
            xmpp_atSession := false;
            //登录成功后要发第一个请求
            xmpp_send_string(s_presence);
            //对方应该回应什么?
        end;//if 2
        //*)
        
    end;//if 1


end;

//presence - 联机状态 //来自 https://www.cnblogs.com/hellowzd/p/4152176.html
//
//联机状态信息包含在一个联机状态（presence）节中。如果 type 属性省略，那么 XMPP 客户端应用程序假定用户在线且可用。否则，type 可设置为 unavailable，或者特定于 pubsub 的值：subscribe、subscribed、unsubscribe 和 unsubscribed。它也可以是针对另一个用户的联机状态信息的一个错误或探针。
//
//一个联机状态节可以包含以下子元素：
//
//show：一个机器可读的值，表示要显示的在线状态的总体类别。这可以是 away（暂时离开）、chat（可用且有兴趣交流）、dnd（请勿打扰）、或 xa（长时间离开）。
//status：一个可读的 show 值。该值为用户可定义的字符串。
//priority：一个位于 -128 到 127 之间的值，定义消息路由到用户的优先顺序。如果值为负数，用户的消息将被扣留。
//
//例如，清单 6 中的 boreduser@somewhere 可以用这个节来表明聊天意愿：
//
//
//清单 6. 样例联机状态通知
//
//<presence xml:lang="en">
//<show>chat</show>
//<status>Bored out of my mind</status>
//<priority>1</priority>
//</presence>
//
//注意 from 属性此处省略。
//
//另一个用户 friendlyuser@somewhereelse 可以通过发送 清单 7 中的节来探测 boreduser@somewhere 的状态：
//
//清单 7. 探测用户状态
//
//<presence type="probe" from="friendlyuser@somewhereelse" to="boreduser@somewhere"/>
//Boreduser@somewhere's server would then respond with a tailored presence response:
//<presence xml:lang="en" from="boreduser@somewhere" to="friendlyuser@somewhereelse">
//<show>chat</show>
//<status>Bored out of my mind</status>
//<priority>1</priority>
//</presence>
//
//这些联机状态值源自 “个人-个人” 消息传递软件。show 元素的值 — 通常用于确定将向其他用户显示的状态图标 — 在聊天应用程序之外如何使用现在还不清楚。状态值可能会在微博工具中找到用武之地；例如，Google Talk（一个 XMPP 聊天服务）中的用户状态字段的更改可以被导入为 Google Buzz 中的微博条目。
//另一种可能性就是将状态值用作每用户应用程序状态数据的携带者。尽管此规范将状态定义为可读，但没有什么能够阻止您在那里存储任意字符串来满足您的要求。对于某些应用程序而言，它可以不是可读的，或者，它可以携带微格式形态的数据负载。
//您可以为一个 XMPP 实体拥有的每个资源独立设置联机状态信息，以便访问和接收连接到一个应用程序中的单个用户的所有工具和上下文的数据只需一个用户帐户。每个资源都可以被分配一个独立的优先级；XMPP 服务器将首先尝试将消息传递给优先级较高的资源。



end.
