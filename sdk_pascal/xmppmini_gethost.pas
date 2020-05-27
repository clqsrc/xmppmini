unit xmppmini_gethost;

//xmppmini 规范获得 xmpp 连接地址的实现

interface

uses
  {}inifiles,{}Windows, Messages, SysUtils, Classes, Graphics, Controls, Forms, Dialogs,
  StdCtrls, uFormVSkin, pngextra_buttonEx, ExtCtrls, pngimage,
  base64,Des, ShellAPI, 
  xmldom, XMLIntf, msxmldom, XMLDoc, Sockets, WinSock,
  uImagePanel, uColorBorderEdit, pngcheckbox, uColorCheckBox, uTHttpThread,
  uTCLQHttpThreadControl;

function GetXmppMiniHost(host:string):Boolean;
//存在文件 http://127.0.0.1:8888/html/xmppmini.txt  即认为是 newbt 的专用服务器
function CheckXmppMiniHost(host:string):Boolean;

var
  gXmppMiniHost:TStringList = nil;

  gXmppMini_web_url_login:string;
  gXmppMini_web_url_his:string;
  gXmppMini_web_url_his_peer:string;
  gXmppMini_web_url_user_admin:string; //用户各种信息管理的页面
  gXmppMini_web_url_upload_image:string; //聊天图片上传页面

implementation

uses form_pass1, xmMain, uConfig;

var
  gGetXmppMiniHost_count:Integer = 0; //读取了多少次，我们定两次为好

procedure GetXmppMiniHost_OnOK(const out1:string;succeed1:boolean);
var
  server_dyn:Integer;
  host:string;
begin

  gXmppMiniHost.Text := out1;

  if True = succeed1  then
  begin
    gXmppMini_web_url_login := Trim(gXmppMiniHost.Values['web_url_login']); //历史收取的信息
    gXmppMini_web_url_his := Trim(gXmppMiniHost.Values['web_url_his']); //历史收取的信息
    gXmppMini_web_url_his_peer := Trim(gXmppMiniHost.Values['web_url_his_peer']); //历史收取的信息
    gXmppMini_web_url_user_admin := Trim(gXmppMiniHost.Values['web_url_user_admin']); //
    gXmppMini_web_url_upload_image := Trim(gXmppMiniHost.Values['web_url_upload_image']); //

    //2020 是否重发
    server_dyn := StrToIntDef(Trim(gXmppMiniHost.Values['server_dyn']), 0); //如果是动态服务器就重发
    host := Trim(gXmppMiniHost.Values['host']);
    if (1 = server_dyn) then
    if gGetXmppMiniHost_count<2 then
    begin
      GetXmppMiniHost(host);
      Exit; //不要再走到下面去连接了
    end;

  end
  else //没有取得的话，用默认 xmppmini 服务器的
  begin
    gXmppMini_web_url_login := 'http://' + GUserHost + ':8888/mail/login.php'; //登录的地址
    gXmppMini_web_url_his := 'http://' + GUserHost + ':8888/mail/login.php?url=user_xmpp_his.php'; //历史收取的信息
    //gXmppMini_web_url_his_peer := 'http://' + GUserHost + ':8888/mail/login.php?url=user_xmpp_his.php?action=peer'; //历史收取的信息
    gXmppMini_web_url_his_peer := 'http://' + GUserHost + ':8888/mail/login.php?url=user_xmpp_his.php%3Faction=peer'; //历史收取的信息//参数中的 [?] 要使用 httpencode 即 [%3F]

    //----
    gXmppMini_web_url_login := 'http://' + GUserHost + ':8888/mail/login.php'; //登录的地址
    gXmppMini_web_url_his := 'http://' + GUserHost + ':8888/mail/user_xmpp_his.php'; //历史收取的信息
    //gXmppMini_web_url_his_peer := 'http://' + GUserHost + ':8888/mail/login.php?url=user_xmpp_his.php?action=peer'; //历史收取的信息
    gXmppMini_web_url_his_peer := 'http://' + GUserHost + ':8888/mail/user_xmpp_his.php?action=peer'; //历史收取的信息//参数中的 [?] 要使用 httpencode 即 [%3F]

    //gXmppMini_web_url_user_admin := 'http://' + GUserHost + ':8888/html/user_admin.html?baseurl=http://192.168.0.112:8888';
    gXmppMini_web_url_user_admin := 'http://' + GUserHost + ':8888/html/user_admin.html?baseurl=http://' + GUserHost + ':8888';

    gXmppMini_web_url_upload_image := 'http://' + GUserHost + ':8888/html/upload_image.html'; //
  end;

  //ShowMessage(out1);
  Form_pass.StartLogin;
end;


//文件 http://127.0.0.1:8888/html/xmppmini.txt 中有 'xmppmini'  即认为是 newbt 的专用服务器
procedure CheckXmppMiniHost_OnOK(const out1:string;succeed1:boolean);
begin
  if Pos('xmppmini', out1)>0 then
  begin
    GServerIsXmppMini := True;
  end
  else
  begin
    GServerIsXmppMini := False;
  end;    

  frmMain.ShowUI_xmppmini(GServerIsXmppMini);
end;



function GetXmppMiniHost(host:string):Boolean;
var
  http:TCLQHttpThreadControl;
begin
  Result := False;

  gGetXmppMiniHost_count := gGetXmppMiniHost_count + 1;

  if gXmppMiniHost = nil then gXmppMiniHost := TStringList.Create;
  gXmppMiniHost.Clear;

  gXmppMiniHost.Values['host'] := host;

  //----
  http:=TCLQHttpThreadControl.Create(nil);

  //http.post_url := 'http://' + GUserHost + '/xmppmini.txt';
  http.post_url := 'http://' + host + '/xmppmini.txt';  //第一次的文件名是固定的
  if (gGetXmppMiniHost_count > 1) then http.post_url := host; //第二次及之后的文件名是动态的

  http.is_get := True;

  http.on_ok2 := GetXmppMiniHost_OnOK;

  http.execute;

  //http.Free;

end;

//存在文件 http://127.0.0.1:8888/html/xmppmini.txt  即认为是 newbt 的专用服务器
function CheckXmppMiniHost(host:string):Boolean;
var
  http:TCLQHttpThreadControl;
begin
  Result := False;

  //注意，这个函数不能设置这些内容
  //gGetXmppMiniHost_count := gGetXmppMiniHost_count + 1;

  //if gXmppMiniHost = nil then gXmppMiniHost := TStringList.Create;
  //gXmppMiniHost.Clear;

  //gXmppMiniHost.Values['host'] := host;

  //----
  http:=TCLQHttpThreadControl.Create(nil);

  //http.post_url := 'http://' + GUserHost + '/xmppmini.txt';
  http.post_url := 'http://' + host + ':8888/html/xmppmini.txt';

  http.is_get := True;

  http.on_ok2 := CheckXmppMiniHost_OnOK;

  http.execute;

  //http.Free;

end;

end.
