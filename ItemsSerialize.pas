unit ItemsSerialize;

interface
uses Types, Classes, SysUtils, LibXmlParser;

type
  TDeSerializeExept = class(Exception);

  TItemSerialize = class(TObject)
  public
    SectionType: string;
    // Serialize methods
    procedure StartItem(const Name: string); virtual; abstract;
    procedure SetValue(Value: string); virtual; abstract;
    procedure AddAttribute(const Name, Value: string); virtual; abstract;
    procedure CloseItem(const Name: string); virtual; abstract;
    // Parse methods
    function GetItem(): Boolean; virtual; abstract;
    function GetItemName(): string; virtual; abstract;
    function GetValue(): string; virtual; abstract;
    function AttrCount: Integer; virtual; abstract;
    function GetAttrName(i: integer): string; virtual; abstract;
    function GetAttrValue(i: integer): string; overload; virtual; abstract;
    function GetAttrValue(Name: string): string; overload; virtual; abstract;
  end;

  TXmlNode = record
    Name: string;
    TagData: string;
    Value: string;
  end;

  TXmlItemSerialize = class(TItemSerialize)
  public
    constructor Create(const FileName: string; Mode: Word);
    destructor Destroy(); override;
    // Serialize methods
    procedure StartItem(const Name: string); override;
    procedure SetValue(Value: string); override;
    procedure AddAttribute(const Name, Value: string); override;
    procedure CloseItem(const Name: string); override;
    // Parse methods
    function GetItem(): Boolean; override;
    function GetItemName(): string; override;
    function GetValue(): string; override;
    function AttrCount: Integer; override;
    function GetAttrName(i: integer): string; override;
    function GetAttrValue(i: integer): string; override;
    function GetAttrValue(Name: string): string; override;
  protected
    Level: integer; //
    Nodes: array of TXmlNode;
    FileName: string;
    FStream: TStream;
    XmlParser: TXmlParser;
  private
    function AddString(s: string): Boolean;
    function InitXmlParser(): Boolean;
  end;


  function DupStr(const str: string; Count: integer): string;
  procedure SkipSpaces(var TagEnd: PChar);

  const
    TAB = #9;
    CR = #13#10;
    HEAD_CAPTION = 'SerialPrint  ';
    Version = ': 1.0';
    XML_HEADER = '<?xml version="1.0" encoding="windows-1251"?>';
    MESS_EXEPT_NOT_NODE = '����������� ����������� ����';
    MESS_EXEPT_ERR_PRED = '������� �� �������� - ��� ������������� ����';
    MESS_EXEPT_WRITE_NODE = '������ ��� ������ ����';
    MESS_EXEPT_WRITE_VALUE = '������ ��� ������ �������� ����';

implementation

procedure SkipSpaces(var TagEnd: PChar);
begin
  while TagEnd[0] <= #33 do inc(TagEnd);
end;

function StrPosExt(const Str1, Str2: PChar; Str1Len: DWORD): PChar; assembler;
asm
        PUSH    EDI
        PUSH    ESI
        PUSH    EBX
        OR      EAX,EAX         // Str1
        JE      @@2             // ���� ������ Str1 ����� - �� �����
        OR      EDX,EDX         // Str2
        JE      @@2             // ���� ������ Str2 ����� - �� �����
        MOV     EBX,EAX
        MOV     EDI,EDX         // ��������� �������� ��� SCASB - ��������� Str2
        XOR     AL,AL           // ������� AL

        push ECX                // ����� ������

        MOV     ECX,0FFFFFFFFH  // ������� � �������
        REPNE   SCASB           // ���� ����� ��������� Str2
        NOT     ECX             // ����������� ECX - �������� ����� ������+1
        DEC     ECX             // � ECX - ����� ������� ��������� Str2

        JE      @@2             // ��� ������� ����� - ��� �� �����
        MOV     ESI,ECX         // ��������� ����� ��������� � ESI

        pop ECX

        SUB     ECX,ESI         // ECX == ������� ���� ����� : Str1 - Str2
        JBE     @@2             // ���� ����� �������� ������ ����� ������ - �����
        MOV     EDI,EBX         // EDI  - ������ ������ Str1
        LEA     EBX,[ESI-1]     // EBX - ����� ��������� �����
@@1:    MOV     ESI,EDX         // ESI - �������� ������ Str2
        LODSB                   // �������� ������ ������ ��������� � AL
        REPNE   SCASB           // ���� ���� ������ � ������ EDI
        JNE     @@2             // ���� ������ �� ��������� - �� �����
        MOV     EAX,ECX         // �������� ������� ���� �����
        PUSH    EDI             // �������� ������� �������� ������
        MOV     ECX,EBX
        REPE    CMPSB           // �������� ���������� ������
        POP     EDI
        MOV     ECX,EAX
        JNE     @@1             // ���� ������ �������� - ���� ��������� ���������� ������� �������
        LEA     EAX,[EDI-1]
        JMP     @@3
@@2:    XOR     EAX,EAX
@@3:    POP     EBX
        POP     ESI
        POP     EDI
end;

// �������� ������ �� �������� ����� �����
function DupStr(const str: string; Count: integer): string;
var i: word;
begin
  Result:='';
  for i:=1 to Count do Result := Result + str;
end;

function NormalizeStr(const sData: string): string;
var
  s: string;
begin
  s:=sData;
  if Length(s)>0 then
  begin
    s:=StringReplace(s, '"', '&quot;', [rfReplaceAll]);
    s:=StringReplace(s, '>', '&gt;', [rfReplaceAll]);
    s:=StringReplace(s, '<', '&lt;', [rfReplaceAll]);
  end;
  Result:=s;
end;

constructor TXmlItemSerialize.Create(const FileName: string; Mode: Word);
begin
  Self.FileName:=FileName;
  Level:=-1;
  SetLength(Nodes, Level+1);
  FStream:=nil;
  XmlParser:=nil;
end;

destructor TXmlItemSerialize.Destroy();
begin
  if Assigned(FStream) then FStream.Free();
  if Assigned(XmlParser) then XmlParser.Free();
end;

// ��������� �������� � �������������� ������
function TXmlItemSerialize.AddString(s: string): Boolean;
begin
  Result:=True;
  try
    FStream.Write(PChar(s)[0], Length(s));
  except
    Result:=False;
    //on e : EWriteError do raise TDeSerializeExept.Create(Format(' %s : <%s>', [MESS_EXEPT_WRITE_VALUE, s]));
  end;
end;

//
procedure TXmlItemSerialize.StartItem(const Name: string);
var
  s: string;
begin
  Inc(Level);
  SetLength(Nodes, Level+1);
  Nodes[Level].Name:=Name;
  Nodes[Level].TagData:='';
  Nodes[Level].Value:='';
end;

procedure TXmlItemSerialize.CloseItem(const Name: string);
var
  s: string;
begin
  s:=DupStr(' ', Level)+'<'+Nodes[Level].Name;
  if Length(Nodes[Level].TagData) > 0 then s:=s+' '+Nodes[Level].TagData;
  if Nodes[Level].Value='' then s:=s+' />'
  else
  begin
    s:=s + '>' + Nodes[Level].Value+'</'+Nodes[Level].Name+'>';
  end;
  s:=s+CR;
  if Level > 0 then
    Nodes[Level-1].Value:=Nodes[Level-1].Value+s
  else
  begin
    try
      if not Assigned(FStream) then
      begin
        FStream:=TFileStream.Create(FileName, fmCreate);
        AddString(XML_HEADER+CR);
      end;
      FStream.WriteBuffer(PChar(s)[0], Length(s));
    except
      on e : EWriteError do raise TDeSerializeExept.Create(Format(' %s : <%s>', [MESS_EXEPT_WRITE_NODE, Nodes[Level].Name]));
    end;
  end;
  Dec(Level);
  SetLength(Nodes, Level+1);
end;

procedure TXmlItemSerialize.SetValue(Value: string);
begin
  Nodes[Level].Value:=Value;
end;

procedure TXmlItemSerialize.AddAttribute(const Name, Value: string);
var
  s: string;
begin
  s:=Nodes[Level].TagData;
  if Length(s)>1 then s:=s+' ';
  s:=s+Name+'="'+NormalizeStr(Value)+'"';
  Nodes[Level].TagData:=s;
end;

// Parse methods
function TXmlItemSerialize.InitXmlParser(): Boolean;
begin
  Result:=True;
  if Assigned(XmlParser) then Exit;
  XmlParser:=TXmlParser.Create();
  //XmlParser.Encoding:='';
  XmlParser.Normalize:=True;
  if not XmlParser.LoadFromFile(FileName) then
  begin
    Result:=False;
    Exit;
  end;
  XmlParser.StartScan();
end;

function TXmlItemSerialize.GetItem(): Boolean;
begin
  Result:=False;
  if not InitXmlParser() then Exit;
  Result:=True;
  while XmlParser.Scan() do
  begin
    case XmlParser.CurPartType of
      ptStartTag: Exit;
      ptEmptyTag: Exit;
    end;
  end;
  Result:=False;
end;

function TXmlItemSerialize.GetItemName(): string;
begin
  Result:='';
  if not InitXmlParser() then Exit;
  Result:=XmlParser.CurName;
end;

function TXmlItemSerialize.GetValue(): string;
begin
  Result:='';
  if not InitXmlParser() then Exit;
  Result:=XmlParser.CurContent;
end;

function TXmlItemSerialize.AttrCount(): Integer;
begin
  Result:=-1;
  if not InitXmlParser() then Exit;
  Result:=XmlParser.CurAttr.Count;
end;

function TXmlItemSerialize.GetAttrName(i: integer): string;
begin
  Result:='';
  if not InitXmlParser() then Exit;
  Result:=XmlParser.CurAttr.Name(i);
end;

function TXmlItemSerialize.GetAttrValue(i: integer): string;
begin
  Result:='';
  if not InitXmlParser() then Exit;
  Result:=XmlParser.CurAttr.Value(i);
end;

function TXmlItemSerialize.GetAttrValue(Name: string): string;
begin
  Result:='';
  if not InitXmlParser() then Exit;
  Result:=XmlParser.CurAttr.Value(Name);
end;


end.
