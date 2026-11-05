import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:image_picker/image_picker.dart';
import 'package:url_launcher/url_launcher.dart';
import 'dart:typed_data';
import 'dart:async';
import 'dart:convert';
import 'notificacoes_push_page.dart';
import 'notificacoes_internas_page.dart';
import 'direito_acesso_page.dart';
import 'metricas_page.dart';

// =============================================================================
// CLASSES AUXILIARES E ESTRUTURA DE CONFIGURAÇÕES
// =============================================================================
class PlanoFormData {
  dynamic id;
  final String nomePlanoBase;
  final String tipoUsuario;
  final TextEditingController valorController;
  final TextEditingController valorRecorrenteController;
  final TextEditingController qtdProfissoesController;
  final TextEditingController qtdFotosController;
  final TextEditingController qtdImagensIaController;
  final TextEditingController qtdVideosController;
  final TextEditingController qtdDiasController;
  final TextEditingController qtdDiasRecorrenteController;
  final TextEditingController qtdPostagemController;
  bool ativo;
  bool destaque;
  bool notificacaoEmail;
  bool notificacaoPush;
  bool linkFacebook;
  bool linkInstagram;

  PlanoFormData({
    this.id,
    required this.nomePlanoBase,
    required this.tipoUsuario,
    required String valorInicial,
    required String valorRecorrenteInicial,
    required String qtdProfissoesInicial,
    required String qtdFotosInicial,
    required String qtdImagensIaInicial,
    required String qtdVideosInicial,
    required String qtdDiasInicial,
    required String qtdDiasRecorrenteInicial,
    required String qtdPostagemInicial,
    this.ativo = true,
    this.destaque = false,
    this.notificacaoEmail = false,
    this.notificacaoPush = false,
    this.linkFacebook = false,
    this.linkInstagram = false,
  })  : valorController = TextEditingController(text: valorInicial),
        valorRecorrenteController =
            TextEditingController(text: valorRecorrenteInicial),
        qtdProfissoesController =
            TextEditingController(text: qtdProfissoesInicial),
        qtdFotosController = TextEditingController(text: qtdFotosInicial),
        qtdImagensIaController =
            TextEditingController(text: qtdImagensIaInicial),
        qtdVideosController = TextEditingController(text: qtdVideosInicial),
        qtdDiasController = TextEditingController(text: qtdDiasInicial),
        qtdDiasRecorrenteController =
            TextEditingController(text: qtdDiasRecorrenteInicial),
        qtdPostagemController = TextEditingController(text: qtdPostagemInicial);

  void dispose() {
    valorController.dispose();
    valorRecorrenteController.dispose();
    qtdProfissoesController.dispose();
    qtdFotosController.dispose();
    qtdImagensIaController.dispose();
    qtdVideosController.dispose();
    qtdDiasController.dispose();
    qtdDiasRecorrenteController.dispose();
    qtdPostagemController.dispose();
  }
}

// =============================================================================
// RESOLUCAO DO PLANO ATIVO DO USUARIO
// =============================================================================
// Regra:
// 1) tab_usuarios define qual plano esta ativo.
// 2) Se nome_plano_ativo for Teste/Cortesia/Parceria/Especial, plano_id aponta
//    para tab_planos_manuais.
// 3) Para qualquer outro nome, plano_id aponta para tab_planos.
// 4) Nunca altera status/ativo da tab_planos ao liberar um plano manual.
class PlanoAtivoResolver {
  static const Set<String> _nomesPlanosManuais = {
    'teste',
    'cortesia',
    'parceria',
    'especial',
  };

  static bool _statusAtivo(dynamic valor) {
    if (valor == null) return false;
    if (valor is bool) return valor;
    final texto = valor.toString().trim().toLowerCase();
    return texto == 'ativo' || texto == 'true' || texto == '1' || texto == 't';
  }

  static DateTime? _data(dynamic valor) {
    if (valor == null) return null;
    return DateTime.tryParse(valor.toString());
  }

  static bool _ehPlanoManual(dynamic nomePlano) {
    final nome = (nomePlano ?? '').toString().trim().toLowerCase();
    return _nomesPlanosManuais.contains(nome);
  }

  static Future<Map<String, dynamic>?> buscarPlanoAtivoDoUsuario(
    dynamic usuarioId,
  ) async {
    if (usuarioId == null || usuarioId.toString().trim().isEmpty) return null;

    final supabase = Supabase.instance.client;

    try {
      final usuario = await supabase
          .from('tab_usuarios')
          .select('id, nome_plano_ativo, plano_id, id_plano_atual')
          .eq('id', usuarioId)
          .maybeSingle();

      if (usuario == null) return null;

      final nomePlanoAtivo =
          (usuario['nome_plano_ativo'] ?? '').toString().trim();
      final dynamic planoId = usuario['plano_id'] ?? usuario['id_plano_atual'];

      if (planoId == null || planoId.toString().trim().isEmpty) return null;

      if (_ehPlanoManual(nomePlanoAtivo)) {
        final response = await supabase
            .from('tab_planos_manuais')
            .select('*')
            .eq('id', planoId)
            .eq('usuario_id', usuarioId)
            .maybeSingle();

        if (response == null) return null;

        final plano = Map<String, dynamic>.from(response);
        final agora = DateTime.now();
        final inicio = _data(plano['data_inicio']);
        final fim = _data(plano['data_fim']);
        final iniciou = inicio == null || !agora.isBefore(inicio.toLocal());
        final naoVenceu = fim == null || !agora.isAfter(fim.toLocal());
        final statusOk = _statusAtivo(plano['status']) ||
            (plano['status'] == null && _statusAtivo(plano['ativo']));

        if (!statusOk || !iniciou || !naoVenceu) return null;

        return <String, dynamic>{
          ...plano,
          '_origem_plano': 'tab_planos_manuais',
          '_plano_manual': true,
        };
      }

      final response = await supabase
          .from('tab_planos')
          .select('*')
          .eq('id', planoId)
          .maybeSingle();

      if (response == null) return null;

      final plano = Map<String, dynamic>.from(response);
      final status = plano['status'];
      final ativo = plano['ativo'];
      final estaAtivo = status == null && ativo == null
          ? true
          : (_statusAtivo(status) || _statusAtivo(ativo));

      if (!estaAtivo) return null;

      return <String, dynamic>{
        ...plano,
        '_origem_plano': 'tab_planos',
        '_plano_manual': false,
      };
    } catch (e) {
      debugPrint('Erro ao resolver plano ativo do usuario: $e');
      return null;
    }
  }
}

class ConfiguracoesPage extends StatefulWidget {
  const ConfiguracoesPage({super.key});

  @override
  State<ConfiguracoesPage> createState() => _ConfiguracoesPageState();
}

class _ConfiguracoesPageState extends State<ConfiguracoesPage>
    with TickerProviderStateMixin {
  TabController? _mainTabController;
  late TabController _planosTabController;
  Timer? _inactivityTimer;

  Map<String, bool> _permissoesAdminLogado = {};

  final Map<String, List<PlanoFormData>> _dadosPlanosPorCategoria = {};

  final List<String> _categorias = [
    'cliente',
    'profissional',
    'arquiteto',
    'engenheiro'
  ];

  final Map<String, List<String>> _nomesPlanosPorCategoria = {
    'cliente': ['gratis', 'essencial', 'pro', 'master'],
    'profissional': ['gratis', 'alicerce', 'mestre', 'topo'],
    'arquiteto': ['gratis', 'croqui', 'conceito', 'masterplan'],
    'engenheiro': ['gratis', 'base', 'carga', 'estrutural'],
  };

  bool _carregando = true;
  bool _mostrarPerfisNoFeed = false;

  // CONTROLE GLOBAL DE NOTIFICAÇÃO PUSH DE NOVAS OPORTUNIDADES
  bool _notificacaoOportunidadePushAtiva = false;
  bool _salvandoNotificacaoOportunidadePush = false;
  // Permite ampliar a area de trabalho das campanhas Push.
  bool _mostrarCabecalhoPush = false;

  // CONTROLLERS E ESTADOS DE CAMPANHAS DE PREMIAÇÃO
  final TextEditingController _tituloCampanhaController =
      TextEditingController();
  final TextEditingController _descricaoPremioController =
      TextEditingController();
  final TextEditingController _regrasCampanhaController =
      TextEditingController();

  DateTime? _dataInicioCampanha;
  DateTime? _dataFimCampanha;
  Uint8List? _imageBytesCampanha;
  String? _imageNameCampanha;
  String? _imagemUrlExistenteCampanha;
  String? _campanhaEditandoId;
  bool _salvandoCampanha = false;
  bool _carregandoCampanhas = false;
  List<Map<String, dynamic>> _listaCampanhas = [];

  // CONTROLLERS E ESTADOS DE ADMINISTRADORES
  final TextEditingController _nomeAdminController = TextEditingController();
  final TextEditingController _emailAdminController = TextEditingController();
  final TextEditingController _cpfAdminController = TextEditingController();
  String? _adminEditandoId;
  List<Map<String, dynamic>> _listaAdmins = [];
  bool _carregandoAdmins = false;

  // CONTROLLERS E ESTADOS DE USUÁRIOS
  final TextEditingController _buscaUsuarioController = TextEditingController();
  List<Map<String, dynamic>> _listaUsuarios = [];
  bool _carregandoUsuarios = false;
  String _filtroTipoUsuario = 'todos';

  // CONTROLLERS E ESTADOS DOS PLANOS MANUAIS
  final TextEditingController _buscaUsuarioPlanoManualController =
      TextEditingController();
  final TextEditingController _limiteServicosManualController =
      TextEditingController(text: '0');
  final TextEditingController _limiteFotosManualController =
      TextEditingController(text: '0');
  final TextEditingController _limiteVideosManualController =
      TextEditingController(text: '0');
  final TextEditingController _limiteImagensIaManualController =
      TextEditingController(text: '0');
  final TextEditingController _limitePostagensManualController =
      TextEditingController(text: '0');
  final TextEditingController _diasLiberacaoManualController =
      TextEditingController(text: '30');
  final TextEditingController _observacaoPlanoManualController =
      TextEditingController();
  final List<String> _nomesPlanosManuais = const [
    'Teste',
    'Cortesia',
    'Parceria',
    'Especial',
  ];
  String _nomePlanoManualSelecionado = 'Teste';
  Map<String, dynamic>? _usuarioPlanoManualSelecionado;
  dynamic _planoManualEditandoId;
  bool _carregandoPlanosManuais = false;
  bool _salvandoPlanoManual = false;
  List<Map<String, dynamic>> _listaPlanosManuais = [];

  // BENEFICIOS E RECURSOS DOS PLANOS MANUAIS
  bool _destaqueManual = false;
  bool _notificacaoEmailManual = false;
  bool _notificacaoPushManual = false;
  bool _linkFacebookManual = false;
  bool _linkInstagramManual = false;

  // CONTROLLERS E ESTADOS DO SELO DE VERIFICAÇÃO
  bool _carregandoSelos = true;
  String _filtroStatusSelo = 'pendente';
  List<Map<String, dynamic>> _solicitacoesSelos = [];

  final TextEditingController _valorSeloController =
      TextEditingController(text: 'R\$ 49,90');
  final TextEditingController _validadeSeloController =
      TextEditingController(text: '365');
  final TextEditingController _prazoSeloController =
      TextEditingController(text: 'Até 3 dias úteis');
  bool _salvandoConfigSelo = false;

  String _tipoAlcance = 'brasil';
  final List<String> _listaEstadosBrasil = [
    'AC',
    'AL',
    'AP',
    'AM',
    'BA',
    'CE',
    'DF',
    'ES',
    'GO',
    'MA',
    'MT',
    'MS',
    'MG',
    'PA',
    'PB',
    'PR',
    'PE',
    'PI',
    'RJ',
    'RN',
    'RS',
    'RO',
    'RR',
    'SC',
    'SP',
    'SE',
    'TO'
  ];
  final Set<String> _estadosSelecionados = {};
  final Set<String> _cidadesSelecionadas = {};

  @override
  void initState() {
    super.initState();
    _resetInactivityTimer();
    _planosTabController =
        TabController(length: _categorias.length, vsync: this);
    _inicializarEstruturaVazia();
    _inicializarDados();
  }

  Future<void> _inicializarDados() async {
    try {
      _permissoesAdminLogado =
          await DireitoAcessoPage.carregarPermissoesAdmin();
    } catch (e) {
      debugPrint('Erro ao carregar permissões do admin: $e');
    }

    await Future.wait([
      _carregarPlanosDoBanco(),
      _carregarPlanosManuais(),
      _carregarAdmins(),
      _carregarUsuarios(),
      _carregarConfiguracoesFeed(),
      _carregarConfiguracaoNotificacaoOportunidadePush(),
      _carregarSolicitacoesSelos(),
      _carregarConfiguracoesSelo(),
      _carregarCampanhas(),
    ]);

    if (mounted) {
      setState(() {
        _carregando = false;
      });
    }
  }

  void _resetInactivityTimer() {
    _inactivityTimer?.cancel();
    _inactivityTimer =
        Timer(const Duration(minutes: 5), _deslogarPorInatividade);
  }

  Future<void> _deslogarPorInatividade() async {
    if (!mounted) return;
    _inactivityTimer?.cancel();
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (e) {
      debugPrint('Erro ao deslogar por inatividade: $e');
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Sessão encerrada por inatividade (5 minutos).'),
        backgroundColor: Colors.orange,
      ),
    );
    _fecharOuRedirecionar();
  }

  Future<void> _fazerLogoutManual() async {
    _inactivityTimer?.cancel();
    try {
      await Supabase.instance.client.auth.signOut();
    } catch (e) {
      debugPrint('Erro ao deslogar: $e');
    }
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text('Sessão encerrada com sucesso!'),
        backgroundColor: Colors.green,
      ),
    );
    _fecharOuRedirecionar();
  }

  void _fecharOuRedirecionar() {
    if (!mounted) return;
    try {
      Navigator.of(context).pushNamedAndRemoveUntil('/', (route) => false);
    } catch (e) {
      if (mounted && Navigator.of(context).canPop()) {
        Navigator.of(context).pop();
      }
    }
  }

  Future<void> _carregarConfiguracoesSelo() async {
    try {
      final response = await Supabase.instance.client
          .from('tab_configuracoes')
          .select('valor_selo, validade_selo, prazo_analise')
          .maybeSingle();

      if (response != null && mounted) {
        setState(() {
          _valorSeloController.text =
              response['valor_selo']?.toString() ?? 'R\$ 49,90';
          _validadeSeloController.text =
              response['validade_selo']?.toString() ?? '365';
          _prazoSeloController.text =
              response['prazo_analise']?.toString() ?? 'Até 3 dias úteis';
        });
      }
    } catch (e) {
      debugPrint('Erro ao carregar configurações do selo: $e');
    }
  }

  Future<void> _salvarConfiguracoesSelo() async {
    setState(() => _salvandoConfigSelo = true);
    try {
      final supabase = Supabase.instance.client;

      final valStr = _valorSeloController.text.trim();
      final validadeStr = _validadeSeloController.text.trim();
      final prazoStr = _prazoSeloController.text.trim();

      final res =
          await supabase.from('tab_configuracoes').select('id').maybeSingle();

      final dadosConfig = {
        'valor_selo': valStr,
        'validade_selo': validadeStr,
        'prazo_analise': prazoStr,
      };

      if (res != null) {
        await supabase
            .from('tab_configuracoes')
            .update(dadosConfig)
            .eq('id', res['id']);
      } else {
        await supabase.from('tab_configuracoes').insert(dadosConfig);
      }

      try {
        await supabase.from('tab_planos_selos').upsert({
          'id': 1,
          'valor': valStr,
          'validade': validadeStr,
          'prazo_analise': prazoStr,
          'status': 'ativo',
        });
      } catch (e2) {
        debugPrint('Aviso: tab_planos_selos não atualizada: $e2');
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Configurações do Selo salvas com sucesso!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao salvar configurações do selo: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _salvandoConfigSelo = false);
    }
  }

  Future<void> _carregarSolicitacoesSelos() async {
    if (!mounted) return;

    setState(() => _carregandoSelos = true);

    try {
      final client = Supabase.instance.client;

      debugPrint(
          '\n============================================================');
      debugPrint('[SELO ADMIN][DIAGNOSTICO] INICIO DO CARREGAMENTO');
      debugPrint('[SELO ADMIN][DIAGNOSTICO] filtro=$_filtroStatusSelo');
      debugPrint(
          '[SELO ADMIN][DIAGNOSTICO] auth.uid=${client.auth.currentUser?.id}');
      debugPrint(
          '[SELO ADMIN][DIAGNOSTICO] email=${client.auth.currentUser?.email}');
      debugPrint(
          '============================================================');

      List<dynamic> response = [];

      if (_filtroStatusSelo == 'pendente' || _filtroStatusSelo == 'enviado') {
        response = await client.from('tab_selo_verificacao').select('*').or(
              'status.ilike.enviado,status.ilike.pendente,status.ilike.em_analise,status.ilike.em analise',
            );
      } else {
        response = await client
            .from('tab_selo_verificacao')
            .select('*')
            .ilike('status', _filtroStatusSelo);
      }

      debugPrint(
          '[SELO ADMIN][DIAGNOSTICO] tab_selo_verificacao retornou ${response.length} registro(s).');
      debugPrint(
          '[SELO ADMIN][DIAGNOSTICO] resposta completa dos selos: $response');

      final List<Map<String, dynamic>> listaFormatada = [];

      for (final item in response) {
        final itemMap = Map<String, dynamic>.from(item);
        final String usuarioId =
            (itemMap['usuario_id'] ?? '').toString().trim();

        debugPrint(
            '------------------------------------------------------------');
        debugPrint('[SELO ADMIN][DIAGNOSTICO] selo.id=${itemMap['id']}');
        debugPrint(
            '[SELO ADMIN][DIAGNOSTICO] selo.status=${itemMap['status']}');
        debugPrint(
            '[SELO ADMIN][DIAGNOSTICO] selo.usuario_id bruto=${itemMap['usuario_id']}');
        debugPrint(
            '[SELO ADMIN][DIAGNOSTICO] selo.usuario_id normalizado=$usuarioId');
        debugPrint('[SELO ADMIN][DIAGNOSTICO] mapa completo do selo=$itemMap');

        Map<String, dynamic>? usuarioEncontrado;

        if (usuarioId.isNotEmpty) {
          try {
            debugPrint(
                '[SELO ADMIN][DIAGNOSTICO] Consultando tab_usuarios WHERE id = $usuarioId');

            final dynamic usuarioResponse = await client
                .from('tab_usuarios')
                .select('*')
                .eq('id', usuarioId)
                .maybeSingle();

            debugPrint(
                '[SELO ADMIN][DIAGNOSTICO] resposta bruta tab_usuarios=$usuarioResponse');

            if (usuarioResponse != null) {
              usuarioEncontrado = Map<String, dynamic>.from(usuarioResponse);
              debugPrint(
                  '[SELO ADMIN][DIAGNOSTICO] USUARIO ENCONTRADO. id=${usuarioEncontrado['id']}');
              debugPrint(
                  '[SELO ADMIN][DIAGNOSTICO] nome=${usuarioEncontrado['usuario_nome']}');
              debugPrint(
                  '[SELO ADMIN][DIAGNOSTICO] email=${usuarioEncontrado['email']}');
              debugPrint(
                  '[SELO ADMIN][DIAGNOSTICO] dados completos=$usuarioEncontrado');
            } else {
              debugPrint(
                  '[SELO ADMIN][DIAGNOSTICO][ATENCAO] A consulta foi executada sem excecao, mas retornou NULL para id=$usuarioId.');
              debugPrint(
                  '[SELO ADMIN][DIAGNOSTICO][ATENCAO] Isso aponta principalmente para RLS/permissao ou ausencia/inconsistencia do registro visivel para esta sessao.');
            }
          } catch (e, stackTraceUsuario) {
            debugPrint(
                '[SELO ADMIN][DIAGNOSTICO][ERRO] Falha ao consultar tab_usuarios para id=$usuarioId');
            debugPrint('[SELO ADMIN][DIAGNOSTICO][ERRO] $e');
            debugPrint('[SELO ADMIN][DIAGNOSTICO][STACK] $stackTraceUsuario');
          }
        } else {
          debugPrint(
              '[SELO ADMIN][DIAGNOSTICO][ATENCAO] Solicitação ${itemMap['id']} sem usuario_id.');
        }

        itemMap['tab_usuarios'] = usuarioEncontrado ?? <String, dynamic>{};
        itemMap['_usuario_id_resolvido'] = usuarioEncontrado?['id'] ??
            (usuarioId.isNotEmpty ? usuarioId : null);

        debugPrint(
            '[SELO ADMIN][DIAGNOSTICO] tab_usuarios incorporado=${itemMap['tab_usuarios']}');
        debugPrint(
            '[SELO ADMIN][DIAGNOSTICO] _usuario_id_resolvido=${itemMap['_usuario_id_resolvido']}');

        listaFormatada.add(itemMap);
      }

      debugPrint(
          '============================================================');
      debugPrint(
          '[SELO ADMIN][DIAGNOSTICO] listaFormatada=${listaFormatada.length} registro(s)');
      debugPrint('[SELO ADMIN][DIAGNOSTICO] lista final=$listaFormatada');
      debugPrint('[SELO ADMIN][DIAGNOSTICO] FIM DO CARREGAMENTO');
      debugPrint(
          '============================================================\n');

      if (!mounted) return;

      setState(() {
        _solicitacoesSelos = listaFormatada;
        _carregandoSelos = false;
      });
    } catch (e, stackTrace) {
      debugPrint(
          '[SELO ADMIN][DIAGNOSTICO][ERRO GERAL] Erro ao carregar solicitações de selo: $e');
      debugPrint('[SELO ADMIN][DIAGNOSTICO][STACK GERAL] $stackTrace');

      if (!mounted) return;

      setState(() => _carregandoSelos = false);

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao buscar dados do selo: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 6),
        ),
      );
    }
  }

  String _rotuloCampoCadastro(String chave) {
    const rotulos = <String, String>{
      'usuario_nome': 'Nome completo',
      'nome': 'Nome',
      'nome_completo': 'Nome completo',
      'email': 'E-mail',
      'cpf': 'CPF',
      'cnpj': 'CNPJ',
      'razao_social': 'Razão social',
      'nome_fantasia': 'Nome fantasia',
      'telefone': 'Telefone',
      'celular': 'Celular',
      'whatsapp': 'WhatsApp',
      'data_nascimento': 'Data de nascimento',
      'nascimento': 'Data de nascimento',
      'sexo': 'Sexo',
      'usuario_tipo': 'Tipo de usuário',
      'tipo_usuario': 'Tipo de usuário',
      'cep': 'CEP',
      'logradouro': 'Logradouro',
      'endereco': 'Endereço',
      'numero': 'Número',
      'complemento': 'Complemento',
      'bairro': 'Bairro',
      'cidade': 'Cidade',
      'estado': 'Estado',
      'uf': 'UF',
      'profissao': 'Profissão',
      'empresa': 'Empresa',
      'crea': 'CREA',
      'cau': 'CAU',
      'usuario_status': 'Status da conta',
      'status': 'Status',
      'created_at': 'Cadastrado em',
      'updated_at': 'Atualizado em',
    };

    if (rotulos.containsKey(chave)) return rotulos[chave]!;

    final partes = chave.split('_').where((e) => e.isNotEmpty).toList();
    if (partes.isEmpty) return chave;
    final texto = partes.join(' ');
    return texto[0].toUpperCase() + texto.substring(1);
  }

  bool _campoTecnicoCadastro(String chave) {
    const ignorar = <String>{
      'fcm_token',
      'push_ativo',
      'access_token',
      'refresh_token',
      'password',
      'senha',
      'id_plano_atual',
      'plano_id',
      'efi_subscription_id',
      'efi_customer_id',
      'ultimo_notification_token',
      'exclusao_solicitada_em',
    };
    return ignorar.contains(chave);
  }

  String _valorCadastroParaTexto(dynamic valor) {
    if (valor == null) return '';
    if (valor is bool) return valor ? 'Sim' : 'Não';
    if (valor is List) return valor.map((e) => e.toString()).join(', ');
    if (valor is Map) return jsonEncode(valor);

    final texto = valor.toString().trim();
    if (texto.isEmpty) return '';

    if (RegExp(r'^\d{4}-\d{2}-\d{2}T').hasMatch(texto)) {
      try {
        final dt = DateTime.parse(texto).toLocal();
        return '${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year} ${dt.hour.toString().padLeft(2, '0')}:${dt.minute.toString().padLeft(2, '0')}';
      } catch (_) {}
    }

    return texto;
  }

  List<MapEntry<String, String>> _dadosCadastraisOrdenados(
      Map<String, dynamic> usuario) {
    const prioridade = <String>[
      'usuario_nome',
      'nome_completo',
      'nome',
      'email',
      'cpf',
      'cnpj',
      'razao_social',
      'nome_fantasia',
      'data_nascimento',
      'nascimento',
      'telefone',
      'celular',
      'whatsapp',
      'usuario_tipo',
      'tipo_usuario',
      'cep',
      'logradouro',
      'endereco',
      'numero',
      'complemento',
      'bairro',
      'cidade',
      'estado',
      'uf',
      'profissao',
      'empresa',
      'crea',
      'cau',
      'usuario_status',
      'status',
      'created_at',
      'updated_at',
    ];

    final resultado = <MapEntry<String, String>>[];
    final adicionados = <String>{};

    void adicionar(String chave) {
      if (!usuario.containsKey(chave) ||
          adicionados.contains(chave) ||
          _campoTecnicoCadastro(chave)) {
        return;
      }
      final valor = _valorCadastroParaTexto(usuario[chave]);
      if (valor.isEmpty || valor.toLowerCase() == 'null') return;
      resultado.add(MapEntry(_rotuloCampoCadastro(chave), valor));
      adicionados.add(chave);
    }

    for (final chave in prioridade) {
      adicionar(chave);
    }

    final restantes = usuario.keys.toList()..sort();
    for (final chave in restantes) {
      if (chave == 'id' || chave.startsWith('_')) continue;
      adicionar(chave);
    }

    return resultado;
  }

  Widget _buildDadoCadastroCard(String rotulo, String valor) {
    return Container(
      width: 245,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      decoration: BoxDecoration(
        color: const Color(0xFF1A2C42),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            rotulo,
            style: const TextStyle(
              color: Colors.white54,
              fontSize: 10.5,
              fontWeight: FontWeight.w600,
            ),
          ),
          const SizedBox(height: 3),
          SelectableText(
            valor,
            style: const TextStyle(
              color: Colors.white,
              fontSize: 12.5,
              fontWeight: FontWeight.w500,
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _abrirDocumento(String path) async {
    try {
      String cleanedPath = path.trim();

      if (cleanedPath.startsWith('http://') ||
          cleanedPath.startsWith('https://')) {
        final Uri url = Uri.parse(cleanedPath);
        if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
          throw 'Não foi possível abrir o link';
        }
        return;
      }

      if (cleanedPath.startsWith('/')) {
        cleanedPath = cleanedPath.substring(1);
      }

      if (cleanedPath.startsWith('documentos_verificacao/')) {
        cleanedPath = cleanedPath.replaceFirst('documentos_verificacao/', '');
      }

      String finalUrl = '';

      try {
        finalUrl = await Supabase.instance.client.storage
            .from('documentos_verificacao')
            .createSignedUrl(cleanedPath, 3600);
      } catch (err) {
        debugPrint("Tentativa de Signed URL falhou para $cleanedPath: $err");
      }

      if (finalUrl.isEmpty) {
        try {
          finalUrl = Supabase.instance.client.storage
              .from('documentos_verificacao')
              .getPublicUrl(cleanedPath);
        } catch (err) {
          debugPrint("Falha ao gerar Public URL: $err");
        }
      }

      if (finalUrl.isEmpty) {
        throw 'Arquivo não encontrado no Storage';
      }

      final Uri url = Uri.parse(finalUrl);
      if (!await launchUrl(url, mode: LaunchMode.externalApplication)) {
        throw 'Não foi possível abrir o link';
      }
    } catch (e) {
      debugPrint("Erro detalhado ao abrir documento: $e");
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao abrir documento: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 4),
        ),
      );
    }
  }

  Future<void> _atualizarStatusSelo(
      dynamic solicitacaoId, dynamic usuarioId, String novoStatus) async {
    if (solicitacaoId == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('ID da solicitação não encontrado.'),
          backgroundColor: Colors.red,
        ),
      );
      return;
    }

    try {
      bool verificado = (novoStatus == 'verificado');

      if (usuarioId != null && usuarioId.toString().isNotEmpty) {
        await Supabase.instance.client
            .from('tab_usuarios')
            .update({'selo_verificado': verificado}).eq('id', usuarioId);
      }

      final agora = DateTime.now();

      final Map<String, dynamic> dadosAtualizacaoSelo = {
        'status': novoStatus,
        'updated_at': agora.toIso8601String(),
      };

      if (verificado) {
        dadosAtualizacaoSelo['data_aprovacao'] = agora.toIso8601String();

        int diasValidade = 365;
        final textoValidade = _validadeSeloController.text.trim();
        final numDirect = int.tryParse(textoValidade);

        if (numDirect != null) {
          diasValidade = numDirect;
        } else {
          final match = RegExp(r'\d+').firstMatch(textoValidade);
          if (match != null) {
            diasValidade = int.tryParse(match.group(0)!) ?? 365;
          }
        }

        final dataExpiracao = agora.add(Duration(days: diasValidade));
        dadosAtualizacaoSelo['data_expiracao'] =
            dataExpiracao.toIso8601String();
      } else {
        dadosAtualizacaoSelo['data_expiracao'] = null;
      }

      await Supabase.instance.client
          .from('tab_selo_verificacao')
          .update(dadosAtualizacaoSelo)
          .eq('id', solicitacaoId);

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Status atualizado para "$novoStatus" com sucesso!'),
          backgroundColor: Colors.green,
        ),
      );

      _carregarSolicitacoesSelos();
      _carregarUsuarios();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao atualizar status: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  Future<void> _carregarConfiguracoesFeed() async {
    try {
      final response = await Supabase.instance.client
          .from('tab_configuracoes')
          .select('mostra_perfil_feed')
          .maybeSingle();

      if (response != null &&
          response['mostra_perfil_feed'] != null &&
          mounted) {
        setState(() {
          _mostrarPerfisNoFeed = _converterBool(response['mostra_perfil_feed']);
        });
      }
    } catch (e) {
      debugPrint('Aviso: Tabela tab_configuracoes não encontrada ou vazia: $e');
    }
  }

  Future<void> _atualizarMostrarPerfisFeed(bool valor) async {
    setState(() {
      _mostrarPerfisNoFeed = valor;
    });

    try {
      final supabase = Supabase.instance.client;
      final res =
          await supabase.from('tab_configuracoes').select('id').maybeSingle();

      if (res != null) {
        await supabase
            .from('tab_configuracoes')
            .update({'mostra_perfil_feed': valor}).eq('id', res['id']);
      } else {
        await supabase
            .from('tab_configuracoes')
            .insert({'mostra_perfil_feed': valor});
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(valor
              ? "Perfis iniciais ativados no feed com sucesso!"
              : "Perfis iniciais removidos do feed com sucesso!"),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      debugPrint('Erro ao atualizar configuração do feed: $e');
      if (mounted) {
        setState(() {
          _mostrarPerfisNoFeed = !valor;
        });
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao atualizar: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  Future<void> _carregarConfiguracaoNotificacaoOportunidadePush() async {
    try {
      final response = await Supabase.instance.client
          .from('tab_configuracoes')
          .select('notificacao_oportunidade_push_ativa')
          .maybeSingle();

      if (!mounted) return;

      setState(() {
        _notificacaoOportunidadePushAtiva = _converterBool(
          response?['notificacao_oportunidade_push_ativa'],
        );
      });
    } catch (e) {
      debugPrint(
          'Aviso ao carregar controle de notificação de oportunidade: $e');
    }
  }

  Future<void> _atualizarNotificacaoOportunidadePush(bool valor) async {
    if (_salvandoNotificacaoOportunidadePush) return;

    final valorAnterior = _notificacaoOportunidadePushAtiva;

    setState(() {
      _notificacaoOportunidadePushAtiva = valor;
      _salvandoNotificacaoOportunidadePush = true;
    });

    try {
      final supabase = Supabase.instance.client;
      final res =
          await supabase.from('tab_configuracoes').select('id').maybeSingle();

      if (res != null) {
        await supabase.from('tab_configuracoes').update({
          'notificacao_oportunidade_push_ativa': valor,
        }).eq('id', res['id']);
      } else {
        await supabase.from('tab_configuracoes').insert({
          'notificacao_oportunidade_push_ativa': valor,
        });
      }

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            valor
                ? 'Notificações automáticas de novas oportunidades ATIVADAS.'
                : 'Notificações automáticas de novas oportunidades DESATIVADAS.',
          ),
          backgroundColor: valor ? Colors.green : Colors.orange,
        ),
      );
    } catch (e) {
      debugPrint(
          'Erro ao atualizar controle de notificação de oportunidade: $e');

      if (!mounted) return;

      setState(() {
        _notificacaoOportunidadePushAtiva = valorAnterior;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'Erro ao salvar controle de notificação. Verifique se o campo '
            'notificacao_oportunidade_push_ativa existe em tab_configuracoes. Erro: $e',
          ),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 5),
        ),
      );
    } finally {
      if (mounted) {
        setState(() => _salvandoNotificacaoOportunidadePush = false);
      }
    }
  }

  Widget _buildAbaNotificacoesPush() {
    return Column(
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(20, 8, 20, 4),
          child: Row(
            children: [
              const Icon(Icons.notifications_active_outlined,
                  color: Color(0xFFFF8C00), size: 18),
              const SizedBox(width: 8),
              const Expanded(
                child: Text('Gestão de notificações Push',
                    style: TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                        fontWeight: FontWeight.w600)),
              ),
              TextButton.icon(
                onPressed: () => setState(
                    () => _mostrarCabecalhoPush = !_mostrarCabecalhoPush),
                icon: Icon(
                    _mostrarCabecalhoPush
                        ? Icons.expand_less
                        : Icons.expand_more,
                    color: const Color(0xFFFF8C00)),
                label: Text(
                    _mostrarCabecalhoPush
                        ? 'Recolher controles'
                        : 'Exibir controles gerais',
                    style: const TextStyle(color: Color(0xFFFF8C00))),
              ),
            ],
          ),
        ),
        if (_mostrarCabecalhoPush)
          Container(
            width: double.infinity,
            margin: const EdgeInsets.fromLTRB(20, 20, 20, 8),
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFF101B2B),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(
                color: const Color(0xFFFF8C00).withOpacity(0.45),
              ),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                Container(
                  width: 46,
                  height: 46,
                  decoration: BoxDecoration(
                    color: const Color(0xFFFF8C00).withOpacity(0.12),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(
                    Icons.notifications_active,
                    color: Color(0xFFFF8C00),
                    size: 26,
                  ),
                ),
                const SizedBox(width: 14),
                const Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        'Notificação automática de novas oportunidades',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      SizedBox(height: 5),
                      Text(
                        'Controle geral para permitir ou bloquear o envio automático de Push quando surgir uma nova oportunidade. As regras de cidade, serviço, plano e preferência do usuário serão aplicadas na lógica da notificação.',
                        style: TextStyle(
                          color: Colors.white70,
                          fontSize: 12.5,
                          height: 1.35,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(width: 12),
                if (_salvandoNotificacaoOportunidadePush)
                  const SizedBox(
                    width: 28,
                    height: 28,
                    child: CircularProgressIndicator(
                      strokeWidth: 2.5,
                      color: Color(0xFFFF8C00),
                    ),
                  )
                else
                  Switch(
                    value: _notificacaoOportunidadePushAtiva,
                    activeColor: const Color(0xFFFF8C00),
                    onChanged: _atualizarNotificacaoOportunidadePush,
                  ),
              ],
            ),
          ),
        // Os cinco grupos são gerenciados individualmente na tela abaixo.
        // Não altera o cadastro de planos nem o disparo manual de campanhas.
        if (_mostrarCabecalhoPush)
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 10),
            child: Wrap(
              spacing: 8,
              runSpacing: 8,
              children: const [
                _GrupoPushIndicador('Cliente', Icons.person_outline),
                _GrupoPushIndicador('Profissional', Icons.handyman_outlined),
                _GrupoPushIndicador('Arquiteto', Icons.architecture_outlined),
                _GrupoPushIndicador('Engenheiro', Icons.engineering_outlined),
                _GrupoPushIndicador('Jisa IA', Icons.smart_toy_outlined),
              ],
            ),
          ),
        const Expanded(
          child: NotificacoesPushPage(),
        ),
      ],
    );
  }

  void _inicializarEstruturaVazia() {
    for (var cat in _categorias) {
      final listaNomes = _nomesPlanosPorCategoria[cat]!;
      _dadosPlanosPorCategoria[cat] = List.generate(4, (index) {
        return PlanoFormData(
          nomePlanoBase: listaNomes[index],
          tipoUsuario: cat,
          valorInicial: '0.00',
          valorRecorrenteInicial: '0.00',
          qtdProfissoesInicial: '1',
          qtdFotosInicial: '10',
          qtdImagensIaInicial: '0',
          qtdVideosInicial: '0',
          qtdDiasInicial: '30',
          qtdDiasRecorrenteInicial: '365',
          qtdPostagemInicial: '5',
        );
      });
    }
  }

  bool _converterBool(dynamic valorBanco) {
    if (valorBanco == null) return false;
    if (valorBanco is bool) return valorBanco;
    String str = valorBanco.toString().trim().toLowerCase();
    return str == 'sim' || str == 'true' || str == '1' || str == 't';
  }

  String _converterBoolParaString(bool valor, {bool permitirVazio = false}) {
    if (!valor && permitirVazio) return '';
    return valor ? 'sim' : 'nao';
  }

  Future<void> _carregarPlanosDoBanco() async {
    try {
      final response =
          await Supabase.instance.client.from('tab_planos').select();

      if (!mounted) return;
      setState(() {
        for (var registro in response) {
          String nomeCompleto =
              (registro['nome_plano'] ?? '').toString().trim().toLowerCase();
          String tipoUsuarioBanco =
              (registro['tipo_usuario'] ?? '').toString().trim().toLowerCase();

          for (var cat in _categorias) {
            bool correspondeCat = tipoUsuarioBanco == cat ||
                tipoUsuarioBanco == '${cat}s' ||
                nomeCompleto.startsWith(cat);

            if (correspondeCat) {
              for (var plano in _dadosPlanosPorCategoria[cat]!) {
                String chaveUnica = '$cat-${plano.nomePlanoBase}';
                bool matchExato = nomeCompleto == chaveUnica ||
                    nomeCompleto == plano.nomePlanoBase ||
                    (tipoUsuarioBanco == cat &&
                        (nomeCompleto == '$cat-${plano.nomePlanoBase}' ||
                            nomeCompleto.endsWith('-${plano.nomePlanoBase}')));

                if (matchExato) {
                  plano.id = registro['id'];
                  plano.valorController.text =
                      (registro['valor'] ?? 0).toString();
                  plano.valorRecorrenteController.text =
                      (registro['valor_recorrente'] ?? 0).toString();
                  plano.qtdProfissoesController.text =
                      (registro['limite_servicos'] ?? 1).toString();
                  plano.qtdFotosController.text =
                      (registro['limite_fotos'] ?? 10).toString();
                  plano.qtdImagensIaController.text =
                      (registro['limite_imagens_ia'] ?? 0).toString();
                  plano.qtdVideosController.text =
                      (registro['qtde_videos'] ?? 0).toString();
                  plano.qtdDiasController.text =
                      (registro['limite_dias'] ?? 30).toString();
                  plano.qtdDiasRecorrenteController.text =
                      (registro['limite_dias_recorrente'] ?? 365).toString();
                  plano.qtdPostagemController.text =
                      (registro['qtde_postagem'] ?? 5).toString();

                  plano.notificacaoEmail = _converterBool(
                      registro['permite_notificacao_email'] ??
                          registro['notificacao_email']);

                  plano.notificacaoPush =
                      _converterBool(registro['notificacao_push']);

                  plano.linkFacebook =
                      _converterBool(registro['link_facebook']);
                  plano.linkInstagram =
                      _converterBool(registro['link_instagram']);
                  plano.destaque = _converterBool(registro['destaque_no_feed']);

                  var statusBanco = registro['status'];
                  plano.ativo = statusBanco == true ||
                      statusBanco.toString().toLowerCase() == 'ativo' ||
                      statusBanco.toString().toLowerCase() == 'true';
                }
              }
            }
          }
        }
      });
    } catch (e) {
      debugPrint('Erro ao carregar planos nas configurações: $e');
    }
  }

  Future<void> _carregarUsuarios() async {
    if (!mounted) return;
    setState(() => _carregandoUsuarios = true);
    try {
      dynamic builder =
          Supabase.instance.client.from('tab_usuarios').select('*');

      final buscaText = _buscaUsuarioController.text.trim();
      if (buscaText.isNotEmpty) {
        final apenasNumeros = buscaText.replaceAll(RegExp(r'\D'), '');
        String cpfFormatado = '';
        if (apenasNumeros.length == 11) {
          cpfFormatado =
              '${apenasNumeros.substring(0, 3)}.${apenasNumeros.substring(3, 6)}.${apenasNumeros.substring(6, 9)}-${apenasNumeros.substring(9, 11)}';
        }

        if (cpfFormatado.isNotEmpty) {
          builder = builder.or(
              'usuario_nome.ilike.%$buscaText%,email.ilike.%$buscaText%,cpf.ilike.%$buscaText%,cpf.ilike.%$cpfFormatado%');
        } else if (apenasNumeros.isNotEmpty) {
          builder = builder.or(
              'usuario_nome.ilike.%$buscaText%,email.ilike.%$buscaText%,cpf.ilike.%$buscaText%,cpf.ilike.%$apenasNumeros%');
        } else {
          builder = builder.or(
              'usuario_nome.ilike.%$buscaText%,email.ilike.%$buscaText%,cpf.ilike.%$buscaText%');
        }
      }

      if (_filtroTipoUsuario != 'todos') {
        builder = builder.ilike('usuario_tipo', _filtroTipoUsuario);
      }

      dynamic response = await builder;

      if (mounted) {
        setState(() {
          _listaUsuarios = List<Map<String, dynamic>>.from(response);
        });
      }
    } catch (e) {
      debugPrint("Erro ao carregar usuários: $e");
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text("Erro ao carregar usuários: $e"),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _carregandoUsuarios = false);
    }
  }

  Future<void> _atualizarStatusUsuarioBanco(
    dynamic userId,
    String novoStatus, {
    String? motivo,
  }) async {
    final supabase = Supabase.instance.client;

    final idUsuario = userId?.toString().trim() ?? '';
    final statusNormalizado = novoStatus.trim().toLowerCase();

    if (idUsuario.isEmpty) {
      throw Exception('ID do usuário não informado.');
    }

    const statusPermitidos = {
      'ativo',
      'inativo',
      'bloqueado',
      'excluido',
    };

    if (!statusPermitidos.contains(statusNormalizado)) {
      throw Exception('Status de usuário inválido: $novoStatus');
    }

    final adminLogado = supabase.auth.currentUser;

    if (statusNormalizado == 'bloqueado') {
      if (adminLogado == null) {
        throw Exception(
          'Não foi possível identificar o administrador responsável pelo bloqueio.',
        );
      }

      if (motivo == null || motivo.trim().isEmpty) {
        throw Exception('O motivo do bloqueio é obrigatório.');
      }
    }

    try {
      // Atualiza e confirma o status do cadastro.
      final dynamic usuarioAtualizado = await supabase
          .from('tab_usuarios')
          .update({
            'usuario_status': statusNormalizado,
          })
          .eq('id', idUsuario)
          .select('id, usuario_status')
          .maybeSingle();

      if (usuarioAtualizado == null) {
        throw Exception(
          'O usuário não foi atualizado. Verifique as policies/RLS de tab_usuarios.',
        );
      }

      final statusConfirmado = (usuarioAtualizado['usuario_status'] ?? '')
          .toString()
          .trim()
          .toLowerCase();

      if (statusConfirmado != statusNormalizado) {
        throw Exception(
          'O banco não confirmou o novo status do usuário.',
        );
      }

      // ================================================================
      // HISTÓRICO PERMANENTE DE BLOQUEIOS ADMINISTRATIVOS
      // ================================================================
      // Cada bloqueio cria uma nova ocorrência. Nenhum histórico é apagado.
      if (statusNormalizado == 'bloqueado' && adminLogado != null) {
        // Caso exista uma ocorrência administrativa antiga ainda marcada
        // como ativa, encerra-a antes de abrir uma nova. Isso evita dois
        // bloqueios ativos para o mesmo usuário.
        await supabase
            .from('tab_bloqueios')
            .update({
              'status': 'liberado',
              'desbloqueado_em': DateTime.now().toIso8601String(),
              'desbloqueado_por': adminLogado.id,
            })
            .eq('bloqueado_id', idUsuario)
            .eq('status', 'ativo');

        await supabase.from('tab_bloqueios').insert({
          'bloqueado_id': idUsuario,
          'bloqueador_id': adminLogado.id,
          'motivo': motivo!.trim(),
          'status': 'ativo',
          'created_at': DateTime.now().toIso8601String(),
          'desbloqueado_em': null,
          'desbloqueado_por': null,
        });
      }

      // Ao liberar um usuário que estava bloqueado, NÃO apagamos o registro.
      // Apenas encerramos todas as ocorrências ainda ativas.
      if (statusNormalizado != 'bloqueado' && adminLogado != null) {
        await supabase
            .from('tab_bloqueios')
            .update({
              'status': 'liberado',
              'desbloqueado_em': DateTime.now().toIso8601String(),
              'desbloqueado_por': adminLogado.id,
            })
            .eq('bloqueado_id', idUsuario)
            .eq('status', 'ativo');
      }

      debugPrint(
        'STATUS DO USUÁRIO ATUALIZADO: '
        'id=$idUsuario | status=$statusNormalizado'
        '${motivo != null && motivo.trim().isNotEmpty ? ' | motivo registrado no histórico' : ''}',
      );
    } catch (e) {
      debugPrint('ERRO AO ATUALIZAR STATUS NO BANCO: $e');
      rethrow;
    }
  }

  Future<void> _alternarAtivoInativo(
      Map<String, dynamic> usuario, bool ativar) async {
    try {
      final String novoStatus = ativar ? 'ativo' : 'inativo';
      await _atualizarStatusUsuarioBanco(usuario['id'], novoStatus);
      await _carregarUsuarios();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(ativar
              ? "Usuário ATIVADO com sucesso!"
              : "Usuário INATIVADO com sucesso!"),
          backgroundColor: ativar ? Colors.green : Colors.orange,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text("Erro ao alterar status: $e"),
            backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _bloquearOuDesbloquearUsuario(
      Map<String, dynamic> usuario, bool estaBloqueado) async {
    String motivoBloqueio = '';

    if (!estaBloqueado) {
      final controllerMotivo = TextEditingController();
      final bool? confirmou = await showDialog<bool>(
        context: context,
        builder: (context) => AlertDialog(
          backgroundColor: const Color(0xFF101B2B),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: const Row(
            children: [
              Icon(Icons.block, color: Colors.deepOrangeAccent),
              SizedBox(width: 8),
              Text('Bloquear Usuário',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
            ],
          ),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                'Informe o motivo do bloqueio para "${usuario['usuario_nome'] ?? usuario['email'] ?? ''}":',
                style: const TextStyle(color: Colors.white70, fontSize: 13),
              ),
              const SizedBox(height: 12),
              TextField(
                controller: controllerMotivo,
                maxLines: 3,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  hintText:
                      'Ex: Violação dos termos de uso, conta suspensa, etc.',
                  hintStyle: TextStyle(color: Colors.white38, fontSize: 12),
                  filled: true,
                  fillColor: Color(0xFF1A2C42),
                  border: OutlineInputBorder(),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(context).pop(false),
              child: const Text('CANCELAR',
                  style: TextStyle(color: Colors.white70)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.deepOrangeAccent),
              onPressed: () {
                if (controllerMotivo.text.trim().isEmpty) {
                  ScaffoldMessenger.of(context).showSnackBar(
                    const SnackBar(
                      content: Text('Por favor, informe o motivo do bloqueio.'),
                      backgroundColor: Colors.red,
                    ),
                  );
                  return;
                }
                Navigator.of(context).pop(true);
              },
              child: const Text('BLOQUEAR',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      );

      if (confirmou != true) return;
      motivoBloqueio = controllerMotivo.text.trim();
    }

    try {
      final String novoStatus = estaBloqueado ? 'ativo' : 'bloqueado';
      await _atualizarStatusUsuarioBanco(usuario['id'], novoStatus,
          motivo: motivoBloqueio);
      await _carregarUsuarios();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(estaBloqueado
              ? "Usuário DESBLOQUEADO com sucesso!"
              : "Usuário BLOQUEADO com sucesso!"),
          backgroundColor: estaBloqueado ? Colors.green : Colors.deepOrange,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text("Erro ao alterar bloqueio: $e"),
            backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _excluirUsuario(Map<String, dynamic> usuario) async {
    final nomeUser =
        usuario['usuario_nome'] ?? usuario['email'] ?? 'este usuário';

    final bool? confirmou = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF101B2B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text(
          'Confirmar Exclusão',
          style:
              TextStyle(color: Colors.redAccent, fontWeight: FontWeight.bold),
        ),
        content: Text(
          'Deseja marcar o cadastro de "$nomeUser" como EXCLUÍDO?',
          style: const TextStyle(color: Colors.white, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child:
                const Text('CANCELAR', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text('EXCLUIR',
                style: TextStyle(
                    color: Colors.white, fontWeight: FontWeight.bold)),
          ),
        ],
      ),
    );

    if (confirmou != true) return;

    try {
      await _atualizarStatusUsuarioBanco(usuario['id'], 'excluido');
      await _carregarUsuarios();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Usuário marcado como EXCLUÍDO com sucesso!"),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text("Erro ao excluir usuário: $e"),
            backgroundColor: Colors.red),
      );
    }
  }

  String _formatarDataHistorico(dynamic valor) {
    if (valor == null || valor.toString().trim().isEmpty) {
      return 'Não informado';
    }

    final data = DateTime.tryParse(valor.toString());
    if (data == null) return valor.toString();

    final local = data.toLocal();
    String dois(int numero) => numero.toString().padLeft(2, '0');

    return '${dois(local.day)}/${dois(local.month)}/${local.year} '
        '${dois(local.hour)}:${dois(local.minute)}';
  }

  Future<List<Map<String, dynamic>>> _carregarHistoricoBloqueios(
      dynamic userId) async {
    final idUsuario = userId?.toString().trim() ?? '';
    if (idUsuario.isEmpty) return [];

    final dynamic response = await Supabase.instance.client
        .from('tab_bloqueios')
        .select(
          'id, bloqueador_id, bloqueado_id, created_at, motivo, status, '
          'desbloqueado_em, desbloqueado_por',
        )
        .eq('bloqueado_id', idUsuario)
        .order('created_at', ascending: false);

    final historico = List<Map<String, dynamic>>.from(response);

    // Busca os nomes/e-mails dos administradores envolvidos sem depender
    // de relacionamento PostgREST adicional.
    final idsAdministradores = <String>{};

    for (final item in historico) {
      final bloqueadorId = item['bloqueador_id']?.toString();
      final desbloqueadorId = item['desbloqueado_por']?.toString();

      if (bloqueadorId != null && bloqueadorId.isNotEmpty) {
        idsAdministradores.add(bloqueadorId);
      }

      if (desbloqueadorId != null && desbloqueadorId.isNotEmpty) {
        idsAdministradores.add(desbloqueadorId);
      }
    }

    if (idsAdministradores.isEmpty) return historico;

    final Map<String, Map<String, dynamic>> adminsPorId = {};

    // O número de administradores de um histórico tende a ser pequeno.
    // Consultas individuais evitam depender de sintaxe IN/relacionamentos
    // e só são executadas quando o administrador abre os detalhes.
    for (final idAdmin in idsAdministradores) {
      try {
        final admin = await Supabase.instance.client
            .from('tab_usuarios')
            .select('id, usuario_nome, email')
            .eq('id', idAdmin)
            .maybeSingle();

        if (admin != null) {
          adminsPorId[idAdmin] = Map<String, dynamic>.from(admin);
        }
      } catch (e) {
        debugPrint('Não foi possível carregar administrador $idAdmin: $e');
      }
    }

    for (final item in historico) {
      final bloqueadorId = item['bloqueador_id']?.toString() ?? '';
      final desbloqueadorId = item['desbloqueado_por']?.toString() ?? '';

      final adminBloqueio = adminsPorId[bloqueadorId];
      final adminLiberacao = adminsPorId[desbloqueadorId];

      item['_bloqueado_por_nome'] = adminBloqueio?['usuario_nome'] ??
          adminBloqueio?['email'] ??
          (bloqueadorId.isEmpty ? 'Não informado' : bloqueadorId);

      item['_desbloqueado_por_nome'] = adminLiberacao?['usuario_nome'] ??
          adminLiberacao?['email'] ??
          (desbloqueadorId.isEmpty ? null : desbloqueadorId);
    }

    return historico;
  }

  Future<void> _visualizarUsuario(Map<String, dynamic> user) async {
    final nome = user['usuario_nome'] ?? 'Não informado';
    final email = user['email'] ?? 'Sem e-mail';
    final cpf = user['cpf'] ?? 'Não informado';
    final tipo = user['usuario_tipo'] ?? 'Cliente';
    final telefone = user['telefone'] ?? user['celular'] ?? 'Não informado';
    final verificado = _converterBool(user['selo_verificado']);
    final status = user['usuario_status'] ?? user['status'] ?? 'ativo';

    if (!mounted) return;

    showDialog<void>(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: const Color(0xFF101B2B),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: Text(
            'Perfil de $nome',
            style: const TextStyle(
              color: Color(0xFFFF8C00),
              fontWeight: FontWeight.bold,
            ),
          ),
          content: SizedBox(
            width: 650,
            child: FutureBuilder<List<Map<String, dynamic>>>(
              future: _carregarHistoricoBloqueios(user['id']),
              builder: (context, snapshot) {
                final carregando =
                    snapshot.connectionState == ConnectionState.waiting;
                final historico =
                    snapshot.data ?? const <Map<String, dynamic>>[];

                Map<String, dynamic>? bloqueioAtual;
                for (final item in historico) {
                  if ((item['status'] ?? '').toString().trim().toLowerCase() ==
                      'ativo') {
                    bloqueioAtual = item;
                    break;
                  }
                }

                return ConstrainedBox(
                  constraints: const BoxConstraints(maxHeight: 650),
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        const Divider(color: Colors.white24),
                        const SizedBox(height: 8),
                        Text(
                          'Nome: $nome',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 14),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'E-mail: $email',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 14),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'CPF: $cpf',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 14),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Tipo: ${tipo.toString().toUpperCase()}',
                          style: const TextStyle(
                              color: Colors.cyanAccent, fontSize: 14),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Telefone: $telefone',
                          style: const TextStyle(
                              color: Colors.white, fontSize: 14),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Selo de Verificação: ${verificado ? 'VERIFICADO ✔' : 'NÃO VERIFICADO'}',
                          style: TextStyle(
                            color: verificado
                                ? Colors.greenAccent
                                : Colors.white70,
                            fontSize: 14,
                            fontWeight: verificado
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'Status da Conta: ${status.toString().toUpperCase()}',
                          style: TextStyle(
                            color:
                                status.toString().toLowerCase() == 'bloqueado'
                                    ? Colors.redAccent
                                    : Colors.white70,
                            fontSize: 14,
                            fontWeight:
                                status.toString().toLowerCase() == 'bloqueado'
                                    ? FontWeight.bold
                                    : FontWeight.normal,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'ID do Usuário: ${user['id']}',
                          style: const TextStyle(
                              color: Colors.white38, fontSize: 11),
                        ),

                        // Motivo do bloqueio atual em destaque.
                        if (status.toString().toLowerCase() == 'bloqueado') ...[
                          const SizedBox(height: 18),
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(14),
                            decoration: BoxDecoration(
                              color: Colors.redAccent.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(10),
                              border: Border.all(
                                  color: Colors.redAccent.withOpacity(0.6)),
                            ),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Row(
                                  children: [
                                    Icon(Icons.block,
                                        color: Colors.redAccent, size: 18),
                                    SizedBox(width: 8),
                                    Text(
                                      'MOTIVO DO BLOQUEIO ATUAL',
                                      style: TextStyle(
                                        color: Colors.redAccent,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                if (carregando)
                                  const LinearProgressIndicator(
                                    color: Color(0xFFFF8C00),
                                  )
                                else
                                  Text(
                                    bloqueioAtual?['motivo']
                                                ?.toString()
                                                .trim()
                                                .isNotEmpty ==
                                            true
                                        ? bloqueioAtual!['motivo'].toString()
                                        : 'Motivo não registrado para este bloqueio.',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 13,
                                      height: 1.4,
                                    ),
                                  ),
                              ],
                            ),
                          ),
                        ],

                        const SizedBox(height: 22),
                        const Row(
                          children: [
                            Icon(Icons.history,
                                color: Color(0xFFFF8C00), size: 20),
                            SizedBox(width: 8),
                            Text(
                              'HISTÓRICO DE BLOQUEIOS',
                              style: TextStyle(
                                color: Color(0xFFFF8C00),
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                          ],
                        ),
                        const SizedBox(height: 10),

                        if (carregando)
                          const Center(
                            child: Padding(
                              padding: EdgeInsets.all(18),
                              child: CircularProgressIndicator(
                                color: Color(0xFFFF8C00),
                              ),
                            ),
                          )
                        else if (snapshot.hasError)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: Colors.redAccent.withOpacity(0.08),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              'Não foi possível carregar o histórico de bloqueios: '
                              '${snapshot.error}',
                              style: const TextStyle(
                                color: Colors.redAccent,
                                fontSize: 12,
                              ),
                            ),
                          )
                        else if (historico.isEmpty)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(12),
                            decoration: BoxDecoration(
                              color: const Color(0xFF1A2C42),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: const Text(
                              'Nenhum bloqueio registrado para este usuário.',
                              style: TextStyle(
                                color: Colors.white54,
                                fontSize: 12,
                              ),
                            ),
                          )
                        else
                          ...List.generate(historico.length, (index) {
                            final item = historico[index];
                            final statusHistorico = (item['status'] ?? 'ativo')
                                .toString()
                                .trim()
                                .toLowerCase();
                            final estaAtivo = statusHistorico == 'ativo';
                            final motivo =
                                (item['motivo'] ?? 'Motivo não informado')
                                    .toString();
                            final bloqueadoPor = (item['_bloqueado_por_nome'] ??
                                    item['bloqueador_id'] ??
                                    'Não informado')
                                .toString();
                            final desbloqueadoPor =
                                item['_desbloqueado_por_nome']?.toString();

                            return Container(
                              width: double.infinity,
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFF1A2C42),
                                borderRadius: BorderRadius.circular(9),
                                border: Border.all(
                                  color: estaAtivo
                                      ? Colors.redAccent.withOpacity(0.55)
                                      : Colors.white12,
                                ),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    children: [
                                      Icon(
                                        estaAtivo
                                            ? Icons.lock
                                            : Icons.lock_open,
                                        color: estaAtivo
                                            ? Colors.redAccent
                                            : Colors.greenAccent,
                                        size: 16,
                                      ),
                                      const SizedBox(width: 7),
                                      Expanded(
                                        child: Text(
                                          'Bloqueio #${historico.length - index}',
                                          style: const TextStyle(
                                            color: Colors.white,
                                            fontWeight: FontWeight.bold,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ),
                                      Text(
                                        estaAtivo ? 'ATIVO' : 'LIBERADO',
                                        style: TextStyle(
                                          color: estaAtivo
                                              ? Colors.redAccent
                                              : Colors.greenAccent,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 9),
                                  Text(
                                    'Motivo: $motivo',
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontSize: 12,
                                      height: 1.35,
                                    ),
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Bloqueado em: ${_formatarDataHistorico(item['created_at'])}',
                                    style: const TextStyle(
                                        color: Colors.white70, fontSize: 11),
                                  ),
                                  const SizedBox(height: 3),
                                  Text(
                                    'Bloqueado por: $bloqueadoPor',
                                    style: const TextStyle(
                                        color: Colors.white70, fontSize: 11),
                                  ),
                                  if (!estaAtivo) ...[
                                    const SizedBox(height: 3),
                                    Text(
                                      'Liberado em: ${_formatarDataHistorico(item['desbloqueado_em'])}',
                                      style: const TextStyle(
                                          color: Colors.white70, fontSize: 11),
                                    ),
                                    if (desbloqueadoPor != null &&
                                        desbloqueadoPor.trim().isNotEmpty) ...[
                                      const SizedBox(height: 3),
                                      Text(
                                        'Liberado por: $desbloqueadoPor',
                                        style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 11),
                                      ),
                                    ],
                                  ],
                                ],
                              ),
                            );
                          }),
                      ],
                    ),
                  ),
                );
              },
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text(
                'FECHAR',
                style: TextStyle(color: Color(0xFFFF8C00)),
              ),
            ),
          ],
        );
      },
    );
  }

  Future<void> _carregarAdmins() async {
    if (!mounted) return;
    setState(() => _carregandoAdmins = true);
    try {
      final response =
          await Supabase.instance.client.from('tab_admin_users').select('*');

      if (mounted) {
        setState(() {
          _listaAdmins = List<Map<String, dynamic>>.from(response);
        });
      }
    } catch (e) {
      debugPrint("Erro ao carregar admins: $e");
    } finally {
      if (mounted) setState(() => _carregandoAdmins = false);
    }
  }

  Future<void> _salvarOuAtualizarAdmin() async {
    final email = _emailAdminController.text.trim().toLowerCase();
    final nomeDigitado = _nomeAdminController.text.trim();
    final cpfDigitado = _cpfAdminController.text.trim();

    if (email.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("Preencha o e-mail do administrador!"),
            backgroundColor: Colors.red),
      );
      return;
    }

    try {
      if (_adminEditandoId != null) {
        await Supabase.instance.client.from('tab_admin_users').update({
          'nome': nomeDigitado.isNotEmpty ? nomeDigitado : 'Admin',
          'email': email,
          'cpf': cpfDigitado.isNotEmpty ? cpfDigitado : null,
        }).eq('id', _adminEditandoId!);

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("Administrador atualizado com sucesso!"),
              backgroundColor: Colors.green),
        );
      } else {
        final adminExistente = await Supabase.instance.client
            .from('tab_admin_users')
            .select('id')
            .ilike('email', email)
            .maybeSingle();

        if (adminExistente != null) {
          await _carregarAdmins();
          if (!mounted) return;
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content:
                    Text("Este e-mail já está cadastrado como administrador!"),
                backgroundColor: Colors.amber),
          );
          return;
        }

        try {
          await Supabase.instance.client.from('tab_admin_users').insert({
            'nome': nomeDigitado.isNotEmpty ? nomeDigitado : 'Admin',
            'email': email,
            'cpf': cpfDigitado.isNotEmpty ? cpfDigitado : null,
            'cargo': 'atendente',
          });
        } catch (dbErr) {
          if (dbErr.toString().contains('23502') ||
              dbErr.toString().contains('null value in column "id"')) {
            final fallbackId =
                '${DateTime.now().millisecondsSinceEpoch}-${email.hashCode.abs()}';
            await Supabase.instance.client.from('tab_admin_users').insert({
              'id': fallbackId,
              'nome': nomeDigitado.isNotEmpty ? nomeDigitado : 'Admin',
              'email': email,
              'cpf': cpfDigitado.isNotEmpty ? cpfDigitado : null,
              'cargo': 'atendente',
            });
          } else {
            rethrow;
          }
        }

        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text("Administrador cadastrado com sucesso!"),
              backgroundColor: Colors.green),
        );
      }

      _limparFormAdmin();
      await _carregarAdmins();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text("Erro ao salvar admin: $e"),
            backgroundColor: Colors.red),
      );
    }
  }

  void _limparFormAdmin() {
    _nomeAdminController.clear();
    _emailAdminController.clear();
    _cpfAdminController.clear();
    setState(() {
      _adminEditandoId = null;
    });
  }

  void _preencherParaEditar(Map<String, dynamic> admin) {
    setState(() {
      _adminEditandoId = admin['id']?.toString();
      _nomeAdminController.text = admin['nome'] ?? '';
      _emailAdminController.text = admin['email'] ?? '';
      _cpfAdminController.text = admin['cpf'] ?? '';
    });
  }

  void _visualizarAdmin(Map<String, dynamic> admin) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF101B2B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text(
          'Detalhes do Administrador',
          style: TextStyle(
            color: Color(0xFFFF8C00),
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Divider(color: Colors.white24),
            const SizedBox(height: 8),
            Text('Nome: ${admin['nome'] ?? 'Não informado'}',
                style: const TextStyle(color: Colors.white, fontSize: 15)),
            const SizedBox(height: 8),
            Text('E-mail: ${admin['email'] ?? '-'}',
                style: const TextStyle(color: Colors.white, fontSize: 15)),
            const SizedBox(height: 8),
            Text('CPF: ${admin['cpf'] ?? 'Não informado'}',
                style: const TextStyle(color: Colors.white, fontSize: 15)),
            const SizedBox(height: 8),
            Text('ID Interno: ${admin['id'] ?? '-'}',
                style: const TextStyle(color: Colors.white54, fontSize: 12)),
            if (admin['created_at'] != null) ...[
              const SizedBox(height: 6),
              Text('Data Cadastro: ${admin['created_at']}',
                  style: const TextStyle(color: Colors.white54, fontSize: 12)),
            ]
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(),
            child: const Text('FECHAR',
                style: TextStyle(color: Color(0xFFFF8C00))),
          ),
        ],
      ),
    );
  }

  Future<void> _excluirAdmin(Map<String, dynamic> admin) async {
    final nomeAdmin = admin['nome'] ?? admin['email'] ?? 'este administrador';

    final bool? confirmou = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF101B2B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Text(
          'Confirmar Exclusão',
          style: TextStyle(
            color: Colors.redAccent,
            fontWeight: FontWeight.bold,
          ),
        ),
        content: Text(
          'Tem certeza de que deseja remover "$nomeAdmin" do painel de administradores?',
          style: const TextStyle(color: Colors.white, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child:
                const Text('CANCELAR', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.redAccent,
            ),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(
              'EXCLUIR',
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (confirmou != true) return;

    try {
      await Supabase.instance.client
          .from('tab_admin_users')
          .delete()
          .eq('id', admin['id']);
      await _carregarAdmins();
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text("Administrador removido com sucesso!")),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text("Erro ao excluir admin: $e"),
            backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _carregarCampanhas() async {
    if (!mounted) return;
    setState(() => _carregandoCampanhas = true);
    try {
      final response =
          await Supabase.instance.client.from('tab_campanhas').select('*');

      if (mounted) {
        setState(() {
          _listaCampanhas = List<Map<String, dynamic>>.from(response);
        });
      }
    } catch (e) {
      debugPrint("Erro ao carregar campanhas: $e");
    } finally {
      if (mounted) setState(() => _carregandoCampanhas = false);
    }
  }

  Future<void> _selecionarImagemCampanha() async {
    final picker = ImagePicker();
    final pickedFile = await picker.pickImage(source: ImageSource.gallery);
    if (pickedFile != null) {
      final bytes = await pickedFile.readAsBytes();
      if (mounted) {
        setState(() {
          _imageBytesCampanha = bytes;
          _imageNameCampanha = pickedFile.name;
        });
      }
    }
  }

  Future<void> _selecionarDataCampanha(
      BuildContext context, bool isInicio) async {
    final picked = await showDatePicker(
      context: context,
      initialDate: DateTime.now(),
      firstDate: DateTime(2025),
      lastDate: DateTime(2035),
    );
    if (picked != null && mounted) {
      setState(() {
        if (isInicio) {
          _dataInicioCampanha = picked;
        } else {
          _dataFimCampanha = picked;
        }
      });
    }
  }

  void _limparFormCampanha() {
    _tituloCampanhaController.clear();
    _descricaoPremioController.clear();
    _regrasCampanhaController.clear();
    setState(() {
      _campanhaEditandoId = null;
      _imagemUrlExistenteCampanha = null;
      _dataInicioCampanha = null;
      _dataFimCampanha = null;
      _imageBytesCampanha = null;
      _imageNameCampanha = null;
      _estadosSelecionados.clear();
      _cidadesSelecionadas.clear();
      _tipoAlcance = 'brasil';
    });
  }

  void _preencherParaEditarCampanha(Map<String, dynamic> camp) {
    setState(() {
      _campanhaEditandoId = camp['id']?.toString();
      _tituloCampanhaController.text = camp['titulo'] ?? '';
      _descricaoPremioController.text = camp['descricao_premio'] ?? '';
      _regrasCampanhaController.text = camp['regras'] ?? '';
      _imagemUrlExistenteCampanha = camp['imagem_url'];

      if (camp['data_inicio'] != null) {
        _dataInicioCampanha = DateTime.tryParse(camp['data_inicio'].toString());
      }
      if (camp['data_fim'] != null) {
        _dataFimCampanha = DateTime.tryParse(camp['data_fim'].toString());
      }

      _tipoAlcance = camp['tipo_alcance'] ?? 'brasil';

      _estadosSelecionados.clear();
      if (camp['estados_alvo'] != null) {
        _estadosSelecionados.addAll(List<String>.from(camp['estados_alvo']));
      }

      _cidadesSelecionadas.clear();
      if (camp['cidades_alvo'] != null) {
        _cidadesSelecionadas.addAll(List<String>.from(camp['cidades_alvo']));
      }
    });
  }

  Future<void> _salvarNovaCampanha() async {
    if (_tituloCampanhaController.text.isEmpty ||
        _descricaoPremioController.text.isEmpty ||
        _regrasCampanhaController.text.isEmpty ||
        _dataInicioCampanha == null ||
        _dataFimCampanha == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content:
                Text('Preencha título, descrição do prêmio, regras e datas!'),
            backgroundColor: Colors.red),
      );
      return;
    }

    if (_tipoAlcance == 'estados' && _estadosSelecionados.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Selecione pelo menos um estado!'),
            backgroundColor: Colors.red),
      );
      return;
    }

    if (_tipoAlcance == 'cidades' && _cidadesSelecionadas.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Selecione pelo menos uma cidade!'),
            backgroundColor: Colors.red),
      );
      return;
    }

    setState(() => _salvandoCampanha = true);

    try {
      String? imageUrl = _imagemUrlExistenteCampanha;
      if (_imageBytesCampanha != null && _imageNameCampanha != null) {
        final storagePath =
            'campanhas/${DateTime.now().millisecondsSinceEpoch}_$_imageNameCampanha';
        await Supabase.instance.client.storage
            .from('chat_bucket')
            .uploadBinary(storagePath, _imageBytesCampanha!);

        imageUrl = Supabase.instance.client.storage
            .from('chat_bucket')
            .getPublicUrl(storagePath);
      }

      final Map<String, dynamic> dadosCampanha = {
        'titulo': _tituloCampanhaController.text.trim(),
        'descricao_premio': _descricaoPremioController.text.trim(),
        'regras': _regrasCampanhaController.text.trim(),
        'imagem_url': imageUrl,
        'data_inicio': _dataInicioCampanha!.toIso8601String(),
        'data_fim': _dataFimCampanha!.toIso8601String(),
        'tipo_alcance': _tipoAlcance,
        'estados_alvo':
            _tipoAlcance == 'estados' ? _estadosSelecionados.toList() : null,
        'cidades_alvo':
            _tipoAlcance == 'cidades' ? _cidadesSelecionadas.toList() : null,
      };

      if (_campanhaEditandoId != null) {
        await Supabase.instance.client
            .from('tab_campanhas')
            .update(dadosCampanha)
            .eq('id', _campanhaEditandoId!);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Campanha atualizada com sucesso!'),
                backgroundColor: Colors.green),
          );
        }
      } else {
        dadosCampanha['ativa'] = true;

        await Supabase.instance.client
            .from('tab_campanhas')
            .insert(dadosCampanha);

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            const SnackBar(
                content: Text('Campanha salva e publicada com sucesso!'),
                backgroundColor: Colors.green),
          );
        }
      }

      _limparFormCampanha();
      await _carregarCampanhas();
    } catch (e) {
      debugPrint('Erro ao salvar campanha: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Erro ao salvar campanha: $e'),
              backgroundColor: Colors.red),
        );
      }
    } finally {
      if (mounted) setState(() => _salvandoCampanha = false);
    }
  }

  Future<void> _alternarStatusCampanha(
      Map<String, dynamic> camp, bool novoValor) async {
    try {
      await Supabase.instance.client
          .from('tab_campanhas')
          .update({'ativa': novoValor}).eq('id', camp['id']);

      await _carregarCampanhas();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(novoValor
              ? 'Campanha ativada com sucesso!'
              : 'Campanha inativada com sucesso!'),
          backgroundColor: novoValor ? Colors.green : Colors.orange,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text("Erro ao alterar status da campanha: $e"),
            backgroundColor: Colors.red),
      );
    }
  }

  Future<void> _excluirCampanha(Map<String, dynamic> camp) async {
    final titulo = camp['titulo'] ?? 'esta campanha';

    final bool? confirmou = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF101B2B),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
        title: const Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.redAccent),
            SizedBox(width: 8),
            Text(
              'Confirmar Exclusão',
              style: TextStyle(
                color: Colors.redAccent,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
        content: Text(
          'Tem certeza de que deseja excluir permanentemente a campanha "$titulo"?',
          style: const TextStyle(color: Colors.white, fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(context).pop(false),
            child:
                const Text('CANCELAR', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.of(context).pop(true),
            child: const Text(
              'EXCLUIR',
              style:
                  TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
            ),
          ),
        ],
      ),
    );

    if (confirmou != true) return;

    try {
      await Supabase.instance.client
          .from('tab_campanhas')
          .delete()
          .eq('id', camp['id']);

      if (_campanhaEditandoId == camp['id']?.toString()) {
        _limparFormCampanha();
      }

      await _carregarCampanhas();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text("Campanha excluída com sucesso!"),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text("Erro ao excluir campanha: $e"),
            backgroundColor: Colors.red),
      );
    }
  }

  @override
  void dispose() {
    _inactivityTimer?.cancel();
    _mainTabController?.dispose();
    _planosTabController.dispose();
    _tituloCampanhaController.dispose();
    _descricaoPremioController.dispose();
    _regrasCampanhaController.dispose();
    _nomeAdminController.dispose();
    _emailAdminController.dispose();
    _cpfAdminController.dispose();
    _buscaUsuarioController.dispose();
    _buscaUsuarioPlanoManualController.dispose();
    _limiteServicosManualController.dispose();
    _limiteFotosManualController.dispose();
    _limiteVideosManualController.dispose();
    _limiteImagensIaManualController.dispose();
    _limitePostagensManualController.dispose();
    _diasLiberacaoManualController.dispose();
    _observacaoPlanoManualController.dispose();
    _valorSeloController.dispose();
    _validadeSeloController.dispose();
    _prazoSeloController.dispose();
    for (var lista in _dadosPlanosPorCategoria.values) {
      for (var plano in lista) {
        plano.dispose();
      }
    }
    super.dispose();
  }

  String _nomeUsuarioPlanoManual(Map<String, dynamic>? usuario) {
    if (usuario == null) return 'Nenhum usuário selecionado';
    final nome =
        (usuario['usuario_nome'] ?? usuario['nome'] ?? '').toString().trim();
    final email = (usuario['email'] ?? '').toString().trim();
    if (nome.isNotEmpty && email.isNotEmpty) return '$nome • $email';
    if (nome.isNotEmpty) return nome;
    if (email.isNotEmpty) return email;
    return usuario['id']?.toString() ?? 'Usuário';
  }

  int _intManual(TextEditingController controller, {int padrao = 0}) {
    return int.tryParse(controller.text.trim()) ?? padrao;
  }

  Future<Map<String, dynamic>?> _verificarPlanoAtivoUsuario(
      dynamic usuarioId) async {
    final plano = await PlanoAtivoResolver.buscarPlanoAtivoDoUsuario(usuarioId);
    if (plano != null) {
      debugPrint(
        'Plano ativo do usuario $usuarioId: ${plano['nome_plano']} | origem=${plano['_origem_plano']}',
      );
    } else {
      debugPrint('Nenhum plano ativo encontrado para o usuario $usuarioId.');
    }
    return plano;
  }

  Future<void> _carregarPlanosManuais() async {
    if (!mounted) return;
    setState(() => _carregandoPlanosManuais = true);
    try {
      final response = await Supabase.instance.client
          .from('tab_planos_manuais')
          .select('*')
          .order('id', ascending: false);

      final lista = List<Map<String, dynamic>>.from(response);
      for (final plano in lista) {
        final usuarioId = plano['usuario_id']?.toString();
        if (usuarioId == null || usuarioId.isEmpty) continue;
        try {
          final usuario = await Supabase.instance.client
              .from('tab_usuarios')
              .select('id, usuario_nome, email, cpf, usuario_tipo')
              .eq('id', usuarioId)
              .maybeSingle();
          plano['_usuario'] = usuario;
        } catch (_) {}
      }

      if (!mounted) return;
      setState(() => _listaPlanosManuais = lista);
    } catch (e) {
      debugPrint('Erro ao carregar planos manuais: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao carregar planos manuais: $e'),
            backgroundColor: Colors.red,
          ),
        );
      }
    } finally {
      if (mounted) setState(() => _carregandoPlanosManuais = false);
    }
  }

  Future<void> _selecionarUsuarioPlanoManual() async {
    final buscaController = TextEditingController(
      text: _buscaUsuarioPlanoManualController.text,
    );
    List<Map<String, dynamic>> resultados = [];
    bool buscando = false;

    Future<void> buscar(StateSetter setDialogState) async {
      final termo = buscaController.text.trim();
      if (termo.isEmpty) {
        setDialogState(() => resultados = []);
        return;
      }
      setDialogState(() => buscando = true);
      try {
        dynamic query = Supabase.instance.client
            .from('tab_usuarios')
            .select('id, usuario_nome, email, cpf, usuario_tipo');
        final numeros = termo.replaceAll(RegExp(r'\D'), '');
        query = query.or(
          'usuario_nome.ilike.%$termo%,email.ilike.%$termo%,cpf.ilike.%${numeros.isNotEmpty ? numeros : termo}%',
        );
        final response = await query.limit(30);
        setDialogState(() {
          resultados = List<Map<String, dynamic>>.from(response);
          buscando = false;
        });
      } catch (e) {
        setDialogState(() => buscando = false);
      }
    }

    final selecionado = await showDialog<Map<String, dynamic>>(
      context: context,
      builder: (dialogContext) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF101B2B),
          title: const Text(
            'Selecionar usuário cadastrado',
            style: TextStyle(color: Color(0xFFFF8C00)),
          ),
          content: SizedBox(
            width: 650,
            height: 430,
            child: Column(
              children: [
                TextField(
                  controller: buscaController,
                  autofocus: true,
                  style: const TextStyle(color: Colors.white),
                  onSubmitted: (_) => buscar(setDialogState),
                  decoration: InputDecoration(
                    labelText: 'Nome, e-mail ou CPF',
                    labelStyle: const TextStyle(color: Colors.white60),
                    prefixIcon:
                        const Icon(Icons.search, color: Color(0xFFFF8C00)),
                    suffixIcon: IconButton(
                      icon: const Icon(Icons.search, color: Color(0xFFFF8C00)),
                      onPressed: () => buscar(setDialogState),
                    ),
                    filled: true,
                    fillColor: const Color(0xFF1A2C42),
                    border: const OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Expanded(
                  child: buscando
                      ? const Center(
                          child: CircularProgressIndicator(
                            color: Color(0xFFFF8C00),
                          ),
                        )
                      : resultados.isEmpty
                          ? const Center(
                              child: Text(
                                'Digite o nome, e-mail ou CPF e clique em pesquisar.',
                                style: TextStyle(color: Colors.white60),
                                textAlign: TextAlign.center,
                              ),
                            )
                          : ListView.separated(
                              itemCount: resultados.length,
                              separatorBuilder: (_, __) =>
                                  const Divider(color: Colors.white12),
                              itemBuilder: (_, index) {
                                final usuario = resultados[index];
                                return ListTile(
                                  leading: const CircleAvatar(
                                    backgroundColor: Color(0xFF1A2C42),
                                    child: Icon(Icons.person,
                                        color: Color(0xFFFF8C00)),
                                  ),
                                  title: Text(
                                    (usuario['usuario_nome'] ?? 'Sem nome')
                                        .toString(),
                                    style: const TextStyle(color: Colors.white),
                                  ),
                                  subtitle: Text(
                                    '${usuario['email'] ?? ''}\nCPF: ${usuario['cpf'] ?? '-'} • ${usuario['usuario_tipo'] ?? ''}',
                                    style:
                                        const TextStyle(color: Colors.white60),
                                  ),
                                  isThreeLine: true,
                                  onTap: () =>
                                      Navigator.of(dialogContext).pop(usuario),
                                );
                              },
                            ),
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(),
              child: const Text('CANCELAR',
                  style: TextStyle(color: Colors.white70)),
            ),
          ],
        ),
      ),
    );

    buscaController.dispose();
    if (selecionado != null && mounted) {
      setState(() {
        _usuarioPlanoManualSelecionado = selecionado;
        _buscaUsuarioPlanoManualController.text =
            _nomeUsuarioPlanoManual(selecionado);
      });
    }
  }

  void _limparFormularioPlanoManual() {
    setState(() {
      _planoManualEditandoId = null;
      _usuarioPlanoManualSelecionado = null;
      _nomePlanoManualSelecionado = 'Teste';
      _buscaUsuarioPlanoManualController.clear();
      _limiteServicosManualController.text = '0';
      _limiteFotosManualController.text = '0';
      _limiteVideosManualController.text = '0';
      _limiteImagensIaManualController.text = '0';
      _limitePostagensManualController.text = '0';
      _diasLiberacaoManualController.text = '30';
      _observacaoPlanoManualController.clear();
      _destaqueManual = false;
      _notificacaoEmailManual = false;
      _notificacaoPushManual = false;
      _linkFacebookManual = false;
      _linkInstagramManual = false;
    });
  }

  Future<void> _salvarPlanoManual() async {
    final usuario = _usuarioPlanoManualSelecionado;
    if (usuario == null || usuario['id'] == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Selecione primeiro o usuário que receberá o plano.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    final dias = _intManual(_diasLiberacaoManualController, padrao: 30);
    if (dias <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Os dias de liberação devem ser maiores que zero.'),
          backgroundColor: Colors.orange,
        ),
      );
      return;
    }

    setState(() => _salvandoPlanoManual = true);
    try {
      final supabase = Supabase.instance.client;
      final agora = DateTime.now();
      final dataFim = agora.add(Duration(days: dias));
      final adminId = supabase.auth.currentUser?.id;
      final editando = _planoManualEditandoId != null;

      final dados = <String, dynamic>{
        'usuario_id': usuario['id'],
        'nome_plano': _nomePlanoManualSelecionado,
        'tipo_usuario':
            (usuario['usuario_tipo'] ?? '').toString().toLowerCase(),
        'valor': 0,
        'limite_servicos': _intManual(_limiteServicosManualController),
        'limite_fotos': _intManual(_limiteFotosManualController),
        'qtde_videos': _intManual(_limiteVideosManualController),
        'limite_imagens_ia': _intManual(_limiteImagensIaManualController),
        'qtde_postagem': _intManual(_limitePostagensManualController),
        'destaque_no_feed': _destaqueManual,
        'permite_notificacao': _notificacaoEmailManual,
        'notificacao_push': _notificacaoPushManual,
        'link_facebook': _converterBoolParaString(_linkFacebookManual),
        'link_instagram': _converterBoolParaString(_linkInstagramManual),
        'dias_liberacao': dias,
        'data_inicio': agora.toIso8601String(),
        'data_fim': dataFim.toIso8601String(),
        'observacao': _observacaoPlanoManualController.text.trim(),
        'status': 'ativo',
        'ativo': true,
        if (adminId != null) 'criado_por': adminId,
      };

      dynamic idPlanoManual;

      if (!editando) {
        // Um usuario nunca fica com dois planos manuais ativos.
        await supabase
            .from('tab_planos_manuais')
            .update({'ativo': false, 'status': 'inativo'})
            .eq('usuario_id', usuario['id'])
            .eq('ativo', true);

        // Insere e recupera o ID gerado pelo banco. Esse ID passa a ser o
        // plano_id do usuario enquanto o plano manual estiver ativo.
        final inserido = await supabase
            .from('tab_planos_manuais')
            .insert(dados)
            .select('id, nome_plano, data_inicio, data_fim')
            .single();
        idPlanoManual = inserido['id'];
      } else {
        dados.remove('data_inicio');
        dados.remove('criado_por');

        await supabase
            .from('tab_planos_manuais')
            .update(dados)
            .eq('id', _planoManualEditandoId)
            .eq('usuario_id', usuario['id']);
        idPlanoManual = _planoManualEditandoId;
      }

      if (idPlanoManual == null) {
        throw Exception('O banco não retornou o ID do plano manual.');
      }

      // tab_usuarios e a fonte da verdade sobre qual plano esta ativo.
      // Para os quatro planos manuais, plano_id/id_plano_atual recebem o ID
      // da tab_planos_manuais. Nenhum registro da tab_planos e alterado.
      await supabase.from('tab_usuarios').update({
        'nome_plano_ativo': _nomePlanoManualSelecionado,
        'plano_id': idPlanoManual,
        'id_plano_atual': idPlanoManual,
        'plano_data_ativacao': agora.toIso8601String(),
        'plano_expiracao': dataFim.toIso8601String(),
        'recorrente': false,
      }).eq('id', usuario['id']);

      // Confirma que o usuario realmente ficou apontando para o plano manual.
      final confirmacao = await supabase
          .from('tab_usuarios')
          .select('nome_plano_ativo, plano_id, id_plano_atual')
          .eq('id', usuario['id'])
          .maybeSingle();

      final idConfirmado =
          confirmacao?['plano_id'] ?? confirmacao?['id_plano_atual'];
      if (confirmacao == null ||
          idConfirmado.toString() != idPlanoManual.toString()) {
        throw Exception(
          'O plano manual foi salvo, mas não foi possível confirmar a atualização em tab_usuarios.',
        );
      }

      await _carregarPlanosManuais();
      await _carregarUsuarios();
      await _verificarPlanoAtivoUsuario(usuario['id']);

      if (!mounted) return;
      _limparFormularioPlanoManual();
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(editando
              ? 'Plano manual atualizado e mantido como plano ativo do usuário!'
              : 'Plano manual liberado e definido como plano ativo do usuário!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao salvar plano manual: $e'),
          backgroundColor: Colors.red,
          duration: const Duration(seconds: 6),
        ),
      );
    } finally {
      if (mounted) setState(() => _salvandoPlanoManual = false);
    }
  }

  void _editarPlanoManual(Map<String, dynamic> plano) {
    final usuario = plano['_usuario'] is Map
        ? Map<String, dynamic>.from(plano['_usuario'])
        : <String, dynamic>{
            'id': plano['usuario_id'],
            'usuario_nome': 'Usuário ${plano['usuario_id']}',
          };
    final nomeBanco = (plano['nome_plano'] ?? 'Teste').toString();
    final nomeValido = _nomesPlanosManuais.firstWhere(
      (nome) => nome.toLowerCase() == nomeBanco.toLowerCase(),
      orElse: () => 'Teste',
    );
    setState(() {
      _planoManualEditandoId = plano['id'];
      _usuarioPlanoManualSelecionado = usuario;
      _buscaUsuarioPlanoManualController.text =
          _nomeUsuarioPlanoManual(usuario);
      _nomePlanoManualSelecionado = nomeValido;
      _limiteServicosManualController.text =
          (plano['limite_servicos'] ?? 0).toString();
      _limiteFotosManualController.text =
          (plano['limite_fotos'] ?? 0).toString();
      _limiteVideosManualController.text =
          (plano['qtde_videos'] ?? 0).toString();
      _limiteImagensIaManualController.text =
          (plano['limite_imagens_ia'] ?? 0).toString();
      _limitePostagensManualController.text =
          (plano['qtde_postagens'] ?? plano['qtde_postagem'] ?? 0).toString();
      _diasLiberacaoManualController.text =
          (plano['dias_liberacao'] ?? 30).toString();
      _observacaoPlanoManualController.text =
          (plano['observacao'] ?? '').toString();
      _destaqueManual = _converterBool(plano['destaque_no_feed']);
      _notificacaoEmailManual = _converterBool(
          plano['permite_notificacao'] ?? plano['permite_notificacao_email']);
      _notificacaoPushManual = _converterBool(plano['notificacao_push']);
      _linkFacebookManual = _converterBool(plano['link_facebook']);
      _linkInstagramManual = _converterBool(plano['link_instagram']);
    });
  }

  Future<void> _excluirPlanoManual(Map<String, dynamic> plano) async {
    final confirmar = await showDialog<bool>(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF101B2B),
        title: const Text('Excluir plano manual',
            style: TextStyle(color: Colors.redAccent)),
        content: Text(
          'Deseja excluir o plano ${plano['nome_plano'] ?? ''} de ${_nomeUsuarioPlanoManual(plano['_usuario'] is Map ? Map<String, dynamic>.from(plano['_usuario']) : null)}?',
          style: const TextStyle(color: Colors.white),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context, false),
            child:
                const Text('CANCELAR', style: TextStyle(color: Colors.white70)),
          ),
          ElevatedButton(
            style: ElevatedButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () => Navigator.pop(context, true),
            child: const Text('EXCLUIR', style: TextStyle(color: Colors.white)),
          ),
        ],
      ),
    );
    if (confirmar != true) return;

    try {
      final supabase = Supabase.instance.client;
      final usuarioId = plano['usuario_id'];
      final planoManualId = plano['id'];

      // Verifica antes da exclusao se este e o plano que tab_usuarios aponta
      // como plano atual. Isso evita deixar um ID manual inexistente no usuario.
      Map<String, dynamic>? usuarioAtual;
      if (usuarioId != null) {
        final response = await supabase
            .from('tab_usuarios')
            .select(
                'id, usuario_tipo, nome_plano_ativo, plano_id, id_plano_atual')
            .eq('id', usuarioId)
            .maybeSingle();
        if (response != null) {
          usuarioAtual = Map<String, dynamic>.from(response);
        }
      }

      final idAtual =
          usuarioAtual?['plano_id'] ?? usuarioAtual?['id_plano_atual'];
      final manualEraPlanoAtual = idAtual != null &&
          planoManualId != null &&
          idAtual.toString() == planoManualId.toString();

      await supabase
          .from('tab_planos_manuais')
          .delete()
          .eq('id', planoManualId);

      if (manualEraPlanoAtual && usuarioAtual != null) {
        // Ao excluir o manual que estava ativo, retorna o usuario ao plano
        // Gratis da categoria dele. A tab_planos continua intacta.
        final tipoUsuario = (usuarioAtual['usuario_tipo'] ?? '')
            .toString()
            .trim()
            .toLowerCase();
        final planosNormais = await supabase
            .from('tab_planos')
            .select('id, nome_plano, tipo_usuario');

        Map<String, dynamic>? planoGratis;
        for (final item in planosNormais) {
          final p = Map<String, dynamic>.from(item);
          final nome = (p['nome_plano'] ?? '').toString().trim().toLowerCase();
          final tipo =
              (p['tipo_usuario'] ?? '').toString().trim().toLowerCase();
          final nomeEhGratis = nome == 'gratis' ||
              nome == '$tipoUsuario-gratis' ||
              nome.endsWith('-gratis');
          final tipoCompativel = tipoUsuario.isEmpty ||
              tipo == tipoUsuario ||
              tipo == '${tipoUsuario}s' ||
              nome.startsWith('$tipoUsuario-');
          if (nomeEhGratis && tipoCompativel) {
            planoGratis = p;
            break;
          }
        }

        if (planoGratis != null) {
          await supabase.from('tab_usuarios').update({
            'nome_plano_ativo':
                (planoGratis['nome_plano'] ?? 'gratis').toString(),
            'plano_id': planoGratis['id'],
            'id_plano_atual': planoGratis['id'],
            'plano_data_ativacao': DateTime.now().toIso8601String(),
            'plano_expiracao': null,
            'recorrente': false,
          }).eq('id', usuarioId);
        } else {
          // Fallback seguro: nao deixa tab_usuarios apontando para um registro
          // manual que acabou de ser excluido.
          await supabase.from('tab_usuarios').update({
            'nome_plano_ativo': 'gratis',
            'plano_id': null,
            'id_plano_atual': null,
            'plano_data_ativacao': null,
            'plano_expiracao': null,
            'recorrente': false,
          }).eq('id', usuarioId);
        }
      }

      if (_planoManualEditandoId == planoManualId) {
        _limparFormularioPlanoManual();
      }
      await _carregarPlanosManuais();
      await _carregarUsuarios();

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(manualEraPlanoAtual
              ? 'Plano manual excluído. O usuário retornou ao plano Grátis.'
              : 'Plano manual excluído com sucesso!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao excluir plano manual: $e'),
          backgroundColor: Colors.red,
        ),
      );
    }
  }

  void _visualizarPlanoManual(Map<String, dynamic> plano) {
    final usuario = plano['_usuario'] is Map
        ? Map<String, dynamic>.from(plano['_usuario'])
        : null;
    String data(dynamic valor) {
      if (valor == null) return '-';
      try {
        final d = DateTime.parse(valor.toString()).toLocal();
        return '${d.day.toString().padLeft(2, '0')}/${d.month.toString().padLeft(2, '0')}/${d.year}';
      } catch (_) {
        return valor.toString();
      }
    }

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        backgroundColor: const Color(0xFF101B2B),
        title: Text(
          'Plano ${plano['nome_plano'] ?? ''}',
          style: const TextStyle(
              color: Color(0xFFFF8C00), fontWeight: FontWeight.bold),
        ),
        content: SingleChildScrollView(
          child: SelectableText(
            'Usuário: ${_nomeUsuarioPlanoManual(usuario)}\n'
            'Tipo: ${usuario?['usuario_tipo'] ?? plano['tipo_usuario'] ?? '-'}\n\n'
            'Serviços: ${plano['limite_servicos'] ?? 0}\n'
            'Fotos: ${plano['limite_fotos'] ?? 0}\n'
            'Vídeos: ${plano['qtde_videos'] ?? 0}\n'
            'Imagens IA: ${plano['limite_imagens_ia'] ?? 0}\n'
            'Postagens: ${plano['qtde_postagens'] ?? plano['qtde_postagem'] ?? 0}\n'
            'Dias de liberação: ${plano['dias_liberacao'] ?? '-'}\n'
            'Início: ${data(plano['data_inicio'])}\n'
            'Fim: ${data(plano['data_fim'])}\n\n'
            'Perfil em destaque: ${_converterBool(plano['destaque_no_feed']) ? 'Sim' : 'Não'}\n'
            'Notificação por e-mail: ${_converterBool(plano['permite_notificacao'] ?? plano['permite_notificacao_email']) ? 'Sim' : 'Não'}\n'
            'Notificação Push: ${_converterBool(plano['notificacao_push']) ? 'Sim' : 'Não'}\n'
            'Link Facebook: ${_converterBool(plano['link_facebook']) ? 'Sim' : 'Não'}\n'
            'Link Instagram: ${_converterBool(plano['link_instagram']) ? 'Sim' : 'Não'}\n\n'
            'Observação: ${(plano['observacao'] ?? '').toString().isEmpty ? 'Sem observação' : plano['observacao']}',
            style: const TextStyle(color: Colors.white, height: 1.55),
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('FECHAR',
                style: TextStyle(color: Color(0xFFFF8C00))),
          ),
        ],
      ),
    );
  }

  Widget _campoNumeroPlanoManual(
      String label, TextEditingController controller) {
    return SizedBox(
      width: 210,
      child: TextField(
        controller: controller,
        keyboardType: TextInputType.number,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white60),
          filled: true,
          fillColor: const Color(0xFF1A2C42),
          enabledBorder: const OutlineInputBorder(
              borderSide: BorderSide(color: Colors.white24)),
          focusedBorder: const OutlineInputBorder(
              borderSide: BorderSide(color: Color(0xFFFF8C00))),
        ),
      ),
    );
  }

  // Cartões de benefícios: cada controle permanece vinculado ao seu campo.
  Widget _cartaoBeneficio({
    required String titulo,
    required String descricao,
    required IconData icone,
    required bool ativo,
    required ValueChanged<bool> aoAlterar,
    Color corIcone = const Color(0xFFFF8C00),
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF12253A),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                width: 42,
                height: 42,
                decoration: BoxDecoration(
                  color: corIcone.withOpacity(0.16),
                  shape: BoxShape.circle,
                ),
                child: Icon(icone, color: corIcone, size: 24),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Text(titulo,
                    style: const TextStyle(
                        color: Colors.white,
                        fontSize: 13,
                        fontWeight: FontWeight.bold)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          Text(descricao,
              style: const TextStyle(
                  color: Colors.white70, fontSize: 12, height: 1.35)),
          const Spacer(),
          const SizedBox(height: 12),
          Row(
            children: [
              Switch(
                value: ativo,
                activeColor: const Color(0xFFFF8C00),
                onChanged: aoAlterar,
              ),
              const SizedBox(width: 5),
              Flexible(
                child: Text(ativo ? 'Ativado' : 'Desativado',
                    style: TextStyle(
                        color: ativo ? const Color(0xFFFF8C00) : Colors.white60,
                        fontSize: 12,
                        fontWeight: FontWeight.w600)),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // Distribui os cinco cartões em uma linha no desktop e reorganiza no celular.
  Widget _gradeBeneficios(List<Widget> cartoes) {
    return LayoutBuilder(
      builder: (context, constraints) {
        const espacamento = 12.0;
        final largura = constraints.maxWidth;
        final colunas = largura >= 1150
            ? 5
            : largura >= 690
                ? 3
                : largura >= 440
                    ? 2
                    : 1;
        final larguraCartao = (largura - espacamento * (colunas - 1)) / colunas;
        return Wrap(
          spacing: espacamento,
          runSpacing: espacamento,
          children: cartoes
              .map((cartao) => SizedBox(
                    width: larguraCartao,
                    height: 180,
                    child: cartao,
                  ))
              .toList(),
        );
      },
    );
  }

  Widget _switchBeneficioPlanoManual(
      String label, bool value, ValueChanged<bool> onChanged) {
    return SizedBox(
      width: 225,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Expanded(
            child: Text(
              label,
              style: const TextStyle(color: Colors.white70, fontSize: 12.5),
            ),
          ),
          Switch(
            value: value,
            activeColor: const Color(0xFFFF8C00),
            onChanged: onChanged,
          ),
        ],
      ),
    );
  }

  Widget _buildAbaPlanosManuais() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Text(
            'Cadastro de Planos Manuais',
            style: TextStyle(
                color: Color(0xFFFF8C00),
                fontSize: 20,
                fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 6),
          const Text(
            'Libere Teste, Cortesia, Parceria ou Especial para um usuário já cadastrado, sem cobrança.',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 18),
          Container(
            width: double.infinity,
            padding: const EdgeInsets.all(18),
            decoration: BoxDecoration(
              color: const Color(0xFF101B2B),
              borderRadius: BorderRadius.circular(12),
              border: Border.all(color: Colors.white12),
            ),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  _planoManualEditandoId == null
                      ? 'Novo plano manual'
                      : 'Editando plano manual',
                  style: const TextStyle(
                      color: Colors.white,
                      fontSize: 16,
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                      width: 520,
                      child: TextField(
                        controller: _buscaUsuarioPlanoManualController,
                        readOnly: true,
                        onTap: _selecionarUsuarioPlanoManual,
                        style: const TextStyle(color: Colors.white),
                        decoration: InputDecoration(
                          labelText: 'Usuário cadastrado',
                          labelStyle: const TextStyle(color: Colors.white60),
                          hintText: 'Clique para buscar nome, e-mail ou CPF',
                          hintStyle: const TextStyle(color: Colors.white38),
                          prefixIcon: const Icon(Icons.person_search,
                              color: Color(0xFFFF8C00)),
                          suffixIcon: IconButton(
                            onPressed: _selecionarUsuarioPlanoManual,
                            icon: const Icon(Icons.search,
                                color: Color(0xFFFF8C00)),
                          ),
                          filled: true,
                          fillColor: const Color(0xFF1A2C42),
                          border: const OutlineInputBorder(),
                        ),
                      ),
                    ),
                    SizedBox(
                      width: 220,
                      child: DropdownButtonFormField<String>(
                        value: _nomePlanoManualSelecionado,
                        dropdownColor: const Color(0xFF101B2B),
                        style: const TextStyle(color: Colors.white),
                        decoration: const InputDecoration(
                          labelText: 'Plano manual',
                          labelStyle: TextStyle(color: Colors.white60),
                          filled: true,
                          fillColor: Color(0xFF1A2C42),
                          border: OutlineInputBorder(),
                        ),
                        items: _nomesPlanosManuais
                            .map((nome) => DropdownMenuItem(
                                value: nome, child: Text(nome)))
                            .toList(),
                        onChanged: (valor) {
                          if (valor != null)
                            setState(() => _nomePlanoManualSelecionado = valor);
                        },
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 12,
                  runSpacing: 12,
                  children: [
                    _campoNumeroPlanoManual('Quantidade de serviços',
                        _limiteServicosManualController),
                    _campoNumeroPlanoManual(
                        'Quantidade de fotos', _limiteFotosManualController),
                    _campoNumeroPlanoManual(
                        'Quantidade de vídeos', _limiteVideosManualController),
                    _campoNumeroPlanoManual(
                        'Imagens de IA', _limiteImagensIaManualController),
                    _campoNumeroPlanoManual('Quantidade de postagens',
                        _limitePostagensManualController),
                    _campoNumeroPlanoManual(
                        'Dias de liberação', _diasLiberacaoManualController),
                  ],
                ),
                const SizedBox(height: 16),
                Container(
                  width: double.infinity,
                  padding: const EdgeInsets.all(14),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A2C42),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white12),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Benefícios e Recursos do Plano',
                        style: TextStyle(
                          color: Color(0xFFFF8C00),
                          fontWeight: FontWeight.bold,
                          fontSize: 13,
                        ),
                      ),
                      const SizedBox(height: 14),
                      _gradeBeneficios([
                        _cartaoBeneficio(
                            titulo: 'Perfil em Destaque',
                            descricao:
                                'Exibe o perfil do usuário em posição de destaque no app.',
                            icone: Icons.workspace_premium,
                            ativo: _destaqueManual,
                            aoAlterar: (v) =>
                                setState(() => _destaqueManual = v)),
                        _cartaoBeneficio(
                            titulo: 'Notificação por E-mail',
                            descricao:
                                'Envia notificações importantes para o e-mail do usuário.',
                            icone: Icons.mail_outline,
                            ativo: _notificacaoEmailManual,
                            aoAlterar: (v) =>
                                setState(() => _notificacaoEmailManual = v)),
                        _cartaoBeneficio(
                            titulo: 'Notificação Push',
                            descricao:
                                'Envia notificações pelo app no celular do usuário.',
                            icone: Icons.notifications_none,
                            ativo: _notificacaoPushManual,
                            aoAlterar: (v) =>
                                setState(() => _notificacaoPushManual = v)),
                        _cartaoBeneficio(
                            titulo: 'Link Facebook',
                            descricao:
                                'Exibe o link do Facebook no perfil público do usuário.',
                            icone: Icons.facebook,
                            ativo: _linkFacebookManual,
                            corIcone: const Color(0xFF669CFF),
                            aoAlterar: (v) =>
                                setState(() => _linkFacebookManual = v)),
                        _cartaoBeneficio(
                            titulo: 'Link Instagram',
                            descricao:
                                'Exibe o link do Instagram no perfil público do usuário.',
                            icone: Icons.camera_alt_outlined,
                            ativo: _linkInstagramManual,
                            corIcone: const Color(0xFFE879C8),
                            aoAlterar: (v) =>
                                setState(() => _linkInstagramManual = v)),
                      ]),
                    ],
                  ),
                ),
                const SizedBox(height: 16),
                TextField(
                  controller: _observacaoPlanoManualController,
                  maxLines: 3,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Observação',
                    labelStyle: TextStyle(color: Colors.white60),
                    hintText:
                        'Observação interna sobre a liberação deste plano',
                    hintStyle: TextStyle(color: Colors.white38),
                    filled: true,
                    fillColor: Color(0xFF1A2C42),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 16),
                Wrap(
                  spacing: 10,
                  children: [
                    ElevatedButton.icon(
                      style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF8C00),
                          padding: const EdgeInsets.symmetric(
                              horizontal: 20, vertical: 15)),
                      onPressed:
                          _salvandoPlanoManual ? null : _salvarPlanoManual,
                      icon: _salvandoPlanoManual
                          ? const SizedBox(
                              width: 18,
                              height: 18,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2, color: Colors.white))
                          : const Icon(Icons.save, color: Colors.white),
                      label: Text(
                        _planoManualEditandoId == null
                            ? 'LIBERAR PLANO'
                            : 'SALVAR ALTERAÇÕES',
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold),
                      ),
                    ),
                    if (_planoManualEditandoId != null)
                      OutlinedButton.icon(
                        onPressed: _limparFormularioPlanoManual,
                        icon: const Icon(Icons.close, color: Colors.white70),
                        label: const Text('CANCELAR EDIÇÃO',
                            style: TextStyle(color: Colors.white70)),
                      ),
                  ],
                ),
              ],
            ),
          ),
          const SizedBox(height: 26),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text('Planos manuais cadastrados',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 17,
                      fontWeight: FontWeight.bold)),
              IconButton(
                tooltip: 'Atualizar',
                onPressed: _carregarPlanosManuais,
                icon: const Icon(Icons.refresh, color: Color(0xFFFF8C00)),
              ),
            ],
          ),
          const SizedBox(height: 10),
          if (_carregandoPlanosManuais)
            const Center(
                child: Padding(
                    padding: EdgeInsets.all(24),
                    child: CircularProgressIndicator(color: Color(0xFFFF8C00))))
          else if (_listaPlanosManuais.isEmpty)
            Container(
              width: double.infinity,
              padding: const EdgeInsets.all(24),
              decoration: BoxDecoration(
                  color: const Color(0xFF101B2B),
                  borderRadius: BorderRadius.circular(12)),
              child: const Text('Nenhum plano manual cadastrado.',
                  style: TextStyle(color: Colors.white60),
                  textAlign: TextAlign.center),
            )
          else
            ..._listaPlanosManuais.map((plano) {
              final usuario = plano['_usuario'] is Map
                  ? Map<String, dynamic>.from(plano['_usuario'])
                  : null;
              return Container(
                margin: const EdgeInsets.only(bottom: 10),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                    color: const Color(0xFF101B2B),
                    borderRadius: BorderRadius.circular(10),
                    border: Border.all(color: Colors.white12)),
                child: Row(
                  children: [
                    const Icon(Icons.card_membership, color: Color(0xFFFF8C00)),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                              '${plano['nome_plano'] ?? 'Plano'} • ${_nomeUsuarioPlanoManual(usuario)}',
                              style: const TextStyle(
                                  color: Colors.white,
                                  fontWeight: FontWeight.bold)),
                          const SizedBox(height: 4),
                          Text(
                              'Fotos: ${plano['limite_fotos'] ?? 0}  •  Vídeos: ${plano['qtde_videos'] ?? 0}  •  IA: ${plano['limite_imagens_ia'] ?? 0}  •  Dias: ${plano['dias_liberacao'] ?? '-'}',
                              style: const TextStyle(
                                  color: Colors.white60, fontSize: 12)),
                        ],
                      ),
                    ),
                    IconButton(
                        tooltip: 'Visualizar',
                        onPressed: () => _visualizarPlanoManual(plano),
                        icon: const Icon(Icons.visibility,
                            color: Colors.lightBlueAccent)),
                    IconButton(
                        tooltip: 'Editar',
                        onPressed: () => _editarPlanoManual(plano),
                        icon:
                            const Icon(Icons.edit, color: Colors.amberAccent)),
                    IconButton(
                        tooltip: 'Excluir',
                        onPressed: () => _excluirPlanoManual(plano),
                        icon:
                            const Icon(Icons.delete, color: Colors.redAccent)),
                  ],
                ),
              );
            }),
        ],
      ),
    );
  }

  Future<void> _salvarPlanoIndividual(
      String categoria, PlanoFormData plano) async {
    try {
      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(color: Color(0xFFFF8C00)),
        ),
      );

      String nomePlanoComposto = '$categoria-${plano.nomePlanoBase}';

      final dadosParaSalvar = {
        'nome_plano': nomePlanoComposto.toLowerCase(),
        'tipo_usuario': categoria.toLowerCase(),
        'valor':
            double.tryParse(plano.valorController.text.replaceAll(',', '.')) ??
                0.0,
        'valor_recorrente': double.tryParse(
                plano.valorRecorrenteController.text.replaceAll(',', '.')) ??
            0.0,
        'limite_servicos':
            int.tryParse(plano.qtdProfissoesController.text) ?? 0,
        'limite_fotos': int.tryParse(plano.qtdFotosController.text) ?? 0,
        'limite_imagens_ia':
            int.tryParse(plano.qtdImagensIaController.text) ?? 0,
        'qtde_videos': int.tryParse(plano.qtdVideosController.text) ?? 0,
        'limite_dias': int.tryParse(plano.qtdDiasController.text) ?? 30,
        'limite_dias_recorrente':
            int.tryParse(plano.qtdDiasRecorrenteController.text) ?? 365,
        'qtde_postagem': int.tryParse(plano.qtdPostagemController.text) ?? 0,
        'permite_notificacao_email': plano.notificacaoEmail,
        'notificacao_push': plano.notificacaoPush,
        'link_facebook': _converterBoolParaString(plano.linkFacebook),
        'link_instagram': _converterBoolParaString(plano.linkInstagram),
        'destaque_no_feed': plano.destaque,
        'status': plano.ativo ? 'ativo' : 'inativo',
      };

      if (plano.id != null) {
        await Supabase.instance.client
            .from('tab_planos')
            .update(dadosParaSalvar)
            .eq('id', plano.id);
      } else {
        final response = await Supabase.instance.client
            .from('tab_planos')
            .insert(dadosParaSalvar)
            .select()
            .single();

        plano.id = response['id'];
      }

      if (mounted) Navigator.of(context, rootNavigator: true).pop();

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Plano "$nomePlanoComposto" salvo com sucesso!'),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (error) {
      if (mounted) Navigator.of(context, rootNavigator: true).pop();
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text('Erro ao salvar plano: $error'),
              backgroundColor: Colors.red),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_carregando) {
      return const Scaffold(
        backgroundColor: Color(0xFF1A2C42),
        body: Center(
          child: CircularProgressIndicator(color: Color(0xFFFF8C00)),
        ),
      );
    }

    final List<Map<String, dynamic>> abasDisponiveis = [
      {
        'key': 'dashboard',
        'tab': const Tab(text: 'Dashboard', icon: Icon(Icons.dashboard)),
        'view': SingleChildScrollView(
          padding: const EdgeInsets.all(24.0),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'Bem-vindo ao Dashboard',
                style: TextStyle(
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                    color: Colors.white),
              ),
              const SizedBox(height: 20),
              Container(
                padding: const EdgeInsets.all(16),
                decoration: BoxDecoration(
                  color: const Color(0xFF101B2B),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.white12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      "Controle do Feed Inicial",
                      style: TextStyle(
                          color: Color(0xFFFF8C00),
                          fontSize: 16,
                          fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      "Ative para exibir novos perfis cadastrados no feed para popular a plataforma temporariamente.",
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                    const SizedBox(height: 15),
                    SwitchListTile(
                      title: const Text(
                        "Mostrar perfis de novos usuários no Feed",
                        style: TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                            fontSize: 14),
                      ),
                      value: _mostrarPerfisNoFeed,
                      activeColor: const Color(0xFFFF8C00),
                      contentPadding: EdgeInsets.zero,
                      onChanged: (bool valor) {
                        _atualizarMostrarPerfisFeed(valor);
                      },
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      },
      {
        'key': 'metricas',
        'tab': const Tab(
          text: 'Métricas',
          icon: Icon(Icons.analytics),
        ),
        'view': const MetricasPage(),
      },
      {
        'key': 'config_planos',
        'tab': const Tab(
            text: 'Configuração dos Planos',
            icon: Icon(Icons.settings_applications)),
        'view': Column(
          children: [
            Container(
              color: const Color(0xFF101B2B),
              child: TabBar(
                controller: _planosTabController,
                isScrollable: true,
                labelColor: const Color(0xFFFF8C00),
                unselectedLabelColor: Colors.white70,
                indicatorColor: const Color(0xFFFF8C00),
                tabs: _categorias
                    .map((cat) =>
                        Tab(text: cat[0].toUpperCase() + cat.substring(1)))
                    .toList(),
              ),
            ),
            Expanded(
              child: TabBarView(
                controller: _planosTabController,
                children: _categorias.map((cat) {
                  return _buildSecaoPlanosPorCategoria(cat);
                }).toList(),
              ),
            ),
          ],
        ),
      },
      {
        'key': 'config_planos',
        'tab': const Tab(
          text: 'Planos Manuais',
          icon: Icon(Icons.card_membership),
        ),
        'view': _buildAbaPlanosManuais(),
      },
      {
        'key': 'premiacao',
        'tab': const Tab(text: 'Premiação', icon: Icon(Icons.emoji_events)),
        'view': _buildAbaPremiacao(),
      },
      {
        'key': 'selo_verificacao',
        'tab':
            const Tab(text: 'Selo de Verificação', icon: Icon(Icons.verified)),
        'view': _buildAbaSeloVerificacao(),
      },
      {
        'key': 'usuarios',
        'tab': const Tab(text: 'Usuários', icon: Icon(Icons.people)),
        'view': _buildAbaUsuarios(),
      },
      {
        // Reutiliza a permissão administrativa de Usuários já existente.
        'key': 'usuarios',
        'tab': const Tab(text: 'Denúncias', icon: Icon(Icons.report_outlined)),
        'view': _PainelDenunciasPerfis(
          onBloquearUsuario: (usuarioId, motivo) async {
            await _atualizarStatusUsuarioBanco(
              usuarioId,
              'bloqueado',
              motivo: motivo,
            );
            await _carregarUsuarios();
          },
        ),
      },
      {
        'key': 'administradores',
        'tab': const Tab(
            text: 'Administradores', icon: Icon(Icons.admin_panel_settings)),
        'view': _buildAbaAdministradores(),
      },
      {
        // Reutiliza o direito de acesso das notificações Push até que
        // uma permissão própria seja cadastrada no módulo de acesso.
        'key': 'notificacoes_push',
        'tab': const Tab(
          text: 'Notificações Internas',
          icon: Icon(Icons.notifications_none_rounded),
        ),
        'view': const NotificacoesInternasPage(),
      },
      {
        'key': 'notificacoes_push',
        'tab': const Tab(
            text: 'Notificações Push', icon: Icon(Icons.notifications_active)),
        'view': _buildAbaNotificacoesPush(),
      },
    ];

    final abasFiltradas = abasDisponiveis.where((aba) {
      final key = aba['key'] as String;
      if (_permissoesAdminLogado.isEmpty) return true;
      if (_permissoesAdminLogado.values.isNotEmpty &&
          _permissoesAdminLogado.values.every((v) => v == false)) {
        return true;
      }

      // A aba Métricas foi adicionada sem alterar a estrutura atual de
      // Direito de Acesso. Enquanto a permissão específica "metricas"
      // ainda não existir no cadastro de permissões, ela permanece visível.
      // Quando a chave passar a existir, o controle atual assume normalmente.
      if (key == 'metricas' &&
          !_permissoesAdminLogado.containsKey('metricas')) {
        return true;
      }

      return _permissoesAdminLogado[key] == true;
    }).toList();

    if (abasFiltradas.isEmpty) {
      abasFiltradas.add({
        'key': 'vazio',
        'tab': const Tab(text: 'Sem Acesso'),
        'view': const Center(
          child: Text(
            'Você não possui permissão para acessar nenhuma aba deste painel.',
            style: TextStyle(color: Colors.white70, fontSize: 16),
            textAlign: TextAlign.center,
          ),
        ),
      });
    }

    if (_mainTabController == null ||
        _mainTabController!.length != abasFiltradas.length) {
      _mainTabController?.dispose();
      _mainTabController =
          TabController(length: abasFiltradas.length, vsync: this);
    }

    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => _resetInactivityTimer(),
      onPointerMove: (_) => _resetInactivityTimer(),
      child: Scaffold(
        backgroundColor: const Color(0xFF1A2C42),
        appBar: AppBar(
          backgroundColor: const Color(0xFF101B2B),
          title: const Text('Configurações do Sistema',
              style: TextStyle(color: Colors.white)),
          iconTheme: const IconThemeData(color: Colors.white),
          actions: [
            Padding(
              padding: const EdgeInsets.only(right: 12.0),
              child: ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.redAccent.withOpacity(0.2),
                  side: const BorderSide(color: Colors.redAccent),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 14, vertical: 8),
                ),
                onPressed: _fazerLogoutManual,
                icon:
                    const Icon(Icons.logout, color: Colors.redAccent, size: 18),
                label: const Text(
                  'SAIR',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ),
            ),
          ],
          bottom: TabBar(
            controller: _mainTabController,
            isScrollable: true,
            labelColor: const Color(0xFFFF8C00),
            unselectedLabelColor: Colors.white70,
            indicatorColor: const Color(0xFFFF8C00),
            tabs: abasFiltradas.map((aba) => aba['tab'] as Widget).toList(),
          ),
        ),
        body: TabBarView(
          controller: _mainTabController,
          children: abasFiltradas.map((aba) => aba['view'] as Widget).toList(),
        ),
      ),
    );
  }

  Widget _buildAbaUsuarios() {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Gestão de Usuários da Plataforma",
                style: TextStyle(
                    color: Color(0xFFFF8C00),
                    fontSize: 18,
                    fontWeight: FontWeight.bold),
              ),
              IconButton(
                icon: const Icon(Icons.refresh, color: Color(0xFFFF8C00)),
                tooltip: "Atualizar Usuários",
                onPressed: _carregarUsuarios,
              ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Visualize, busque, bloqueie, inative ou altere as contas cadastradas.',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Expanded(
                flex: 3,
                child: TextField(
                  controller: _buscaUsuarioController,
                  style: const TextStyle(color: Colors.white),
                  onSubmitted: (_) => _carregarUsuarios(),
                  decoration: InputDecoration(
                    labelText: "Buscar por Nome, E-mail ou CPF",
                    labelStyle: const TextStyle(color: Colors.white54),
                    prefixIcon:
                        const Icon(Icons.search, color: Color(0xFFFF8C00)),
                    suffixIcon: _buscaUsuarioController.text.isNotEmpty
                        ? IconButton(
                            icon:
                                const Icon(Icons.clear, color: Colors.white54),
                            onPressed: () {
                              _buscaUsuarioController.clear();
                              _carregarUsuarios();
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: const Color(0xFF101B2B),
                    border: const OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              ElevatedButton.icon(
                style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF8C00),
                  padding:
                      const EdgeInsets.symmetric(horizontal: 18, vertical: 20),
                ),
                onPressed: _carregarUsuarios,
                icon: const Icon(Icons.search, color: Colors.white, size: 18),
                label: const Text(
                  "BUSCAR",
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold),
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                flex: 2,
                child: DropdownButtonFormField<String>(
                  value: _filtroTipoUsuario,
                  dropdownColor: const Color(0xFF101B2B),
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: 'Tipo de Usuário',
                    labelStyle: TextStyle(color: Colors.white54),
                    filled: true,
                    fillColor: Color(0xFF101B2B),
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(value: 'todos', child: Text('Todos')),
                    DropdownMenuItem(value: 'cliente', child: Text('Clientes')),
                    DropdownMenuItem(
                        value: 'profissional', child: Text('Profissionais')),
                    DropdownMenuItem(
                        value: 'arquiteto', child: Text('Arquitetos')),
                    DropdownMenuItem(
                        value: 'engenheiro', child: Text('Engenheiros')),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setState(() => _filtroTipoUsuario = val);
                      _carregarUsuarios();
                    }
                  },
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          Row(
            children: [
              Container(
                padding:
                    const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                decoration: BoxDecoration(
                  color: const Color(0xFF101B2B),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white12),
                ),
                child: Text(
                  "Total Encontrado: ${_listaUsuarios.length}",
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          _carregandoUsuarios
              ? const Center(
                  child: Padding(
                      padding: EdgeInsets.all(30),
                      child:
                          CircularProgressIndicator(color: Color(0xFFFF8C00))))
              : _listaUsuarios.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(30),
                      child: Center(
                        child: Text("Nenhum usuário encontrado no banco.",
                            style:
                                TextStyle(color: Colors.white54, fontSize: 15)),
                      ),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _listaUsuarios.length,
                      itemBuilder: (context, index) {
                        final user = _listaUsuarios[index];
                        final nome = user['usuario_nome'] ?? 'Sem Nome';
                        final email = user['email'] ?? 'Sem e-mail';
                        final cpf = user['cpf'] ?? 'Não informado';
                        final tipo =
                            (user['usuario_tipo'] ?? 'cliente').toString();
                        final bool verificado =
                            _converterBool(user['selo_verificado']);

                        final String statusAtual = (user['usuario_status'] ??
                                user['status'] ??
                                'ativo')
                            .toString()
                            .toLowerCase();

                        final bool isExcluido = user['excluido'] == true ||
                            statusAtual == 'excluido' ||
                            statusAtual == 'excluído';
                        final bool isBloqueado = user['bloqueado'] == true ||
                            statusAtual == 'bloqueado';
                        final bool isAtivo = statusAtual == 'ativo' &&
                            !isBloqueado &&
                            !isExcluido;
                        final bool isInativo = statusAtual == 'inativo' ||
                            (!isAtivo && !isBloqueado && !isExcluido);

                        Color statusColor = Colors.greenAccent;
                        String statusTexto = "ATIVO";

                        if (isExcluido) {
                          statusColor = Colors.redAccent;
                          statusTexto = "EXCLUÍDO";
                        } else if (isBloqueado) {
                          statusColor = Colors.deepOrangeAccent;
                          statusTexto = "BLOQUEADO";
                        } else if (isInativo) {
                          statusColor = Colors.amberAccent;
                          statusTexto = "INATIVO";
                        }

                        return Container(
                          margin: const EdgeInsets.symmetric(vertical: 8),
                          decoration: BoxDecoration(
                            color: const Color(0xFF101B2B),
                            borderRadius: BorderRadius.circular(10),
                            border:
                                Border.all(color: statusColor.withOpacity(0.5)),
                          ),
                          child: Column(
                            children: [
                              Container(
                                width: double.infinity,
                                padding: const EdgeInsets.symmetric(
                                    vertical: 6, horizontal: 16),
                                decoration: BoxDecoration(
                                  color: statusColor.withOpacity(0.2),
                                  borderRadius: const BorderRadius.only(
                                    topLeft: Radius.circular(9),
                                    topRight: Radius.circular(9),
                                  ),
                                ),
                                child: Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Text(
                                      "STATUS DO USUÁRIO: $statusTexto",
                                      style: TextStyle(
                                        color: statusColor,
                                        fontWeight: FontWeight.bold,
                                        fontSize: 12,
                                      ),
                                    ),
                                    if (!isAtivo)
                                      TextButton.icon(
                                        style: TextButton.styleFrom(
                                          padding: EdgeInsets.zero,
                                          minimumSize: const Size(50, 20),
                                          tapTargetSize:
                                              MaterialTapTargetSize.shrinkWrap,
                                        ),
                                        onPressed: () =>
                                            _alternarAtivoInativo(user, true),
                                        icon: const Icon(Icons.check_circle,
                                            color: Colors.greenAccent,
                                            size: 14),
                                        label: const Text(
                                          "REATIVAR CONTA",
                                          style: TextStyle(
                                              color: Colors.greenAccent,
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                  ],
                                ),
                              ),
                              ListTile(
                                contentPadding: const EdgeInsets.symmetric(
                                    horizontal: 16, vertical: 8),
                                leading: CircleAvatar(
                                  backgroundColor: const Color(0xFF1A2C42),
                                  child: Text(
                                    nome.isNotEmpty
                                        ? nome[0].toUpperCase()
                                        : 'U',
                                    style: const TextStyle(
                                        color: Color(0xFFFF8C00),
                                        fontWeight: FontWeight.bold),
                                  ),
                                ),
                                title: Row(
                                  children: [
                                    Flexible(
                                      child: Text(
                                        nome,
                                        overflow: TextOverflow.ellipsis,
                                        style: TextStyle(
                                            color: isExcluido
                                                ? Colors.white54
                                                : Colors.white,
                                            fontWeight: FontWeight.bold,
                                            decoration: isExcluido
                                                ? TextDecoration.lineThrough
                                                : null),
                                      ),
                                    ),
                                    if (verificado) ...[
                                      const SizedBox(width: 6),
                                      const Icon(Icons.verified,
                                          color: Colors.blueAccent, size: 16),
                                    ],
                                  ],
                                ),
                                subtitle: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const SizedBox(height: 2),
                                    Text("E-mail: $email",
                                        style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 12)),
                                    Text("CPF: $cpf",
                                        style: const TextStyle(
                                            color: Colors.white70,
                                            fontSize: 12)),
                                    Text("Tipo: ${tipo.toUpperCase()}",
                                        style: const TextStyle(
                                            color: Colors.cyanAccent,
                                            fontSize: 11)),
                                  ],
                                ),
                                trailing: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Column(
                                      mainAxisAlignment:
                                          MainAxisAlignment.center,
                                      children: [
                                        Text(
                                          isAtivo ? "ATIVO" : "INATIVO",
                                          style: TextStyle(
                                            color: isAtivo
                                                ? Colors.greenAccent
                                                : Colors.amberAccent,
                                            fontSize: 10,
                                            fontWeight: FontWeight.bold,
                                          ),
                                        ),
                                        Switch(
                                          value: isAtivo,
                                          activeColor: const Color(0xFFFF8C00),
                                          inactiveThumbColor: Colors.grey,
                                          inactiveTrackColor: Colors.white24,
                                          onChanged: isExcluido
                                              ? null
                                              : (bool valor) =>
                                                  _alternarAtivoInativo(
                                                      user, valor),
                                        ),
                                      ],
                                    ),
                                    const SizedBox(width: 8),
                                    IconButton(
                                      icon: Icon(
                                          isBloqueado
                                              ? Icons.lock_open
                                              : Icons.block,
                                          color: isBloqueado
                                              ? Colors.greenAccent
                                              : Colors.deepOrangeAccent),
                                      tooltip: isBloqueado
                                          ? "Desbloquear Usuário"
                                          : "Bloquear Usuário",
                                      onPressed: isExcluido
                                          ? null
                                          : () => _bloquearOuDesbloquearUsuario(
                                              user, isBloqueado),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.visibility,
                                          color: Color(0xFFFF8C00)),
                                      tooltip: "Ver Detalhes",
                                      onPressed: () => _visualizarUsuario(user),
                                    ),
                                    IconButton(
                                      icon: const Icon(Icons.delete,
                                          color: Colors.redAccent),
                                      tooltip: "Excluir Registro",
                                      onPressed: () => _excluirUsuario(user),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ),
                        );
                      },
                    ),
        ],
      ),
    );
  }

  Widget _buildAbaSeloVerificacao() {
    return Column(
      children: [
        Container(
          padding: const EdgeInsets.all(16),
          color: const Color(0xFF101B2B),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                '⚙️ Configurações Exibidas no App para o Selo',
                style: TextStyle(
                  color: Color(0xFFFF8C00),
                  fontSize: 15,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _valorSeloController,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: const InputDecoration(
                        labelText: 'Valor (Ex: R\$ 49,90 ou Gratuito)',
                        labelStyle:
                            TextStyle(color: Colors.white54, fontSize: 11),
                        filled: true,
                        fillColor: Color(0xFF1A2C42),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _validadeSeloController,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: const InputDecoration(
                        labelText: 'Validade em Dias (Ex: 365)',
                        labelStyle:
                            TextStyle(color: Colors.white54, fontSize: 11),
                        filled: true,
                        fillColor: Color(0xFF1A2C42),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: TextField(
                      controller: _prazoSeloController,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: const InputDecoration(
                        labelText: 'Prazo (Ex: Até 3 dias úteis)',
                        labelStyle:
                            TextStyle(color: Colors.white54, fontSize: 11),
                        filled: true,
                        fillColor: Color(0xFF1A2C42),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                    style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF8C00),
                      padding: const EdgeInsets.symmetric(
                          vertical: 20, horizontal: 16),
                    ),
                    onPressed:
                        _salvandoConfigSelo ? null : _salvarConfiguracoesSelo,
                    child: _salvandoConfigSelo
                        ? const SizedBox(
                            width: 16,
                            height: 16,
                            child: CircularProgressIndicator(
                                color: Colors.white, strokeWidth: 2),
                          )
                        : const Text(
                            'SALVAR',
                            style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
                            ),
                          ),
                  ),
                ],
              ),
            ],
          ),
        ),
        const Divider(color: Colors.white12, height: 1),
        Container(
          color: const Color(0xFF101B2B),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
          child: Row(
            children: [
              _buildFiltroSeloBotao(
                  'Pendentes', 'pendente', Colors.amberAccent),
              const SizedBox(width: 10),
              _buildFiltroSeloBotao(
                  'Verificados', 'verificado', Colors.greenAccent),
              const SizedBox(width: 10),
              _buildFiltroSeloBotao(
                  'Rejeitados', 'rejeitado', Colors.redAccent),
            ],
          ),
        ),
        Expanded(
          child: _carregandoSelos
              ? const Center(
                  child: CircularProgressIndicator(color: Color(0xFFFF8C00)),
                )
              : _solicitacoesSelos.isEmpty
                  ? Center(
                      child: Text(
                        "Nenhuma solicitação encontrada em '$_filtroStatusSelo'.",
                        style: const TextStyle(
                            color: Colors.white54, fontSize: 15),
                      ),
                    )
                  : ListView.builder(
                      padding: const EdgeInsets.all(20),
                      itemCount: _solicitacoesSelos.length,
                      itemBuilder: (context, index) {
                        final item = _solicitacoesSelos[index];
                        final usuarioRaw = item['tab_usuarios'];
                        final Map<String, dynamic> usuario = usuarioRaw is Map
                            ? Map<String, dynamic>.from(usuarioRaw)
                            : (usuarioRaw is List && usuarioRaw.isNotEmpty
                                ? Map<String, dynamic>.from(usuarioRaw.first)
                                : <String, dynamic>{});

                        final nome = (usuario['usuario_nome'] ??
                                usuario['nome_completo'] ??
                                usuario['nome'] ??
                                item['usuario_nome'] ??
                                item['nome'] ??
                                'Usuário não localizado')
                            .toString();
                        final email = (usuario['email'] ??
                                item['email'] ??
                                item['usuario_email'] ??
                                'Sem e-mail')
                            .toString();
                        final caminhoArquivo = item['documento_url'];
                        final caminhoArquivo2 = item['documento_url_2'];
                        final tipoPessoa = item['tipo_pessoa'] ?? 'Fisica';
                        final solicitacaoId = item['id'];
                        final usuarioId = item['_usuario_id_resolvido'] ??
                            item['usuario_id'] ??
                            item['user_id'] ??
                            item['id_usuario'];
                        final statusAtual = item['status'] ?? 'pendente';
                        final dadosCadastrais =
                            _dadosCadastraisOrdenados(usuario);
                        final dataExpiracaoRaw = item['data_expiracao'];
                        final dataAprovacaoRaw = item['data_aprovacao'];

                        String? expiracaoFormatada;
                        if (dataExpiracaoRaw != null &&
                            dataExpiracaoRaw.toString().isNotEmpty) {
                          try {
                            final dt =
                                DateTime.parse(dataExpiracaoRaw.toString())
                                    .toLocal();
                            expiracaoFormatada =
                                "${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}";
                          } catch (_) {}
                        }

                        String? aprovacaoFormatada;
                        if (dataAprovacaoRaw != null &&
                            dataAprovacaoRaw.toString().isNotEmpty) {
                          try {
                            final dt =
                                DateTime.parse(dataAprovacaoRaw.toString())
                                    .toLocal();
                            aprovacaoFormatada =
                                "${dt.day.toString().padLeft(2, '0')}/${dt.month.toString().padLeft(2, '0')}/${dt.year}";
                          } catch (_) {}
                        }

                        return Container(
                          margin: const EdgeInsets.only(bottom: 15),
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: const Color(0xFF101B2B),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Text(
                                    nome,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 16,
                                        fontWeight: FontWeight.bold),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                        horizontal: 8, vertical: 4),
                                    decoration: BoxDecoration(
                                      color: Colors.amber.withOpacity(0.2),
                                      borderRadius: BorderRadius.circular(6),
                                      border: Border.all(
                                        color: Colors.amberAccent,
                                      ),
                                    ),
                                    child: Text(
                                      "Tipo: $tipoPessoa | Status: ${statusAtual.toUpperCase()}",
                                      style: const TextStyle(
                                          color: Colors.amberAccent,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold),
                                    ),
                                  ),
                                ],
                              ),
                              const SizedBox(height: 6),
                              Text(
                                "E-mail: $email",
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 13),
                              ),
                              const SizedBox(height: 10),
                              Container(
                                width: double.infinity,
                                decoration: BoxDecoration(
                                  color: const Color(0xFF16263A),
                                  borderRadius: BorderRadius.circular(10),
                                  border: Border.all(color: Colors.white12),
                                ),
                                child: Theme(
                                  data: Theme.of(context).copyWith(
                                    dividerColor: Colors.transparent,
                                    splashColor: Colors.transparent,
                                    highlightColor: Colors.transparent,
                                  ),
                                  child: ExpansionTile(
                                    initiallyExpanded: true,
                                    tilePadding: const EdgeInsets.symmetric(
                                        horizontal: 14, vertical: 2),
                                    childrenPadding: const EdgeInsets.fromLTRB(
                                        14, 0, 14, 14),
                                    iconColor: const Color(0xFFFF8C00),
                                    collapsedIconColor: const Color(0xFFFF8C00),
                                    leading: const Icon(
                                      Icons.badge_outlined,
                                      color: Color(0xFFFF8C00),
                                      size: 21,
                                    ),
                                    title: const Text(
                                      'Dados cadastrais para conferência',
                                      style: TextStyle(
                                        color: Colors.white,
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    subtitle: Text(
                                      dadosCadastrais.isEmpty
                                          ? 'Cadastro do usuário não foi localizado na tab_usuarios.'
                                          : '${dadosCadastrais.length} campo(s) encontrados na tab_usuarios.',
                                      style: TextStyle(
                                        color: dadosCadastrais.isEmpty
                                            ? Colors.redAccent
                                            : Colors.white54,
                                        fontSize: 11,
                                      ),
                                    ),
                                    children: [
                                      if (dadosCadastrais.isEmpty)
                                        const Align(
                                          alignment: Alignment.centerLeft,
                                          child: Padding(
                                            padding: EdgeInsets.only(top: 6),
                                            child: Text(
                                              'Não foi possível relacionar esta solicitação a um registro de usuário. Verifique o usuario_id gravado em tab_selo_verificacao.',
                                              style: TextStyle(
                                                color: Colors.redAccent,
                                                fontSize: 12,
                                              ),
                                            ),
                                          ),
                                        )
                                      else
                                        Wrap(
                                          spacing: 10,
                                          runSpacing: 10,
                                          children: dadosCadastrais
                                              .map((campo) =>
                                                  _buildDadoCadastroCard(
                                                      campo.key, campo.value))
                                              .toList(),
                                        ),
                                    ],
                                  ),
                                ),
                              ),
                              if (aprovacaoFormatada != null ||
                                  expiracaoFormatada != null) ...[
                                const SizedBox(height: 6),
                                Row(
                                  children: [
                                    if (aprovacaoFormatada != null)
                                      Text(
                                        "Aprovado em: $aprovacaoFormatada",
                                        style: const TextStyle(
                                            color: Colors.white54,
                                            fontSize: 12),
                                      ),
                                    if (aprovacaoFormatada != null &&
                                        expiracaoFormatada != null)
                                      const Text(" | ",
                                          style: TextStyle(
                                              color: Colors.white54,
                                              fontSize: 12)),
                                    if (expiracaoFormatada != null)
                                      Text(
                                        "Válido até: $expiracaoFormatada",
                                        style: const TextStyle(
                                            color: Colors.greenAccent,
                                            fontSize: 12,
                                            fontWeight: FontWeight.bold),
                                      ),
                                  ],
                                ),
                              ],
                              const SizedBox(height: 15),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Row(
                                    children: [
                                      if (caminhoArquivo != null &&
                                          caminhoArquivo.toString().isNotEmpty)
                                        OutlinedButton.icon(
                                          style: OutlinedButton.styleFrom(
                                            side: const BorderSide(
                                                color: Color(0xFFFF8C00)),
                                          ),
                                          onPressed: () =>
                                              _abrirDocumento(caminhoArquivo),
                                          icon: const Icon(Icons.remove_red_eye,
                                              color: Color(0xFFFF8C00),
                                              size: 18),
                                          label: Text(
                                            tipoPessoa == 'Fisica'
                                                ? "Ver Documento"
                                                : "Ver CNPJ",
                                            style: const TextStyle(
                                                color: Color(0xFFFF8C00)),
                                          ),
                                        ),
                                      if (caminhoArquivo2 != null &&
                                          caminhoArquivo2
                                              .toString()
                                              .trim()
                                              .isNotEmpty) ...[
                                        const SizedBox(width: 8),
                                        OutlinedButton.icon(
                                          style: OutlinedButton.styleFrom(
                                            side: const BorderSide(
                                                color: Color(0xFFFF8C00)),
                                          ),
                                          onPressed: () =>
                                              _abrirDocumento(caminhoArquivo2),
                                          icon: const Icon(Icons.remove_red_eye,
                                              color: Color(0xFFFF8C00),
                                              size: 18),
                                          label: const Text(
                                            "Ver Sócio/Doc",
                                            style: TextStyle(
                                                color: Color(0xFFFF8C00)),
                                          ),
                                        ),
                                      ],
                                    ],
                                  ),
                                  Row(
                                    children: [
                                      if (statusAtual != 'rejeitado')
                                        IconButton(
                                          icon: const Icon(Icons.close,
                                              color: Colors.redAccent),
                                          tooltip: "Reprovar / Revogar",
                                          onPressed: () => _atualizarStatusSelo(
                                              solicitacaoId,
                                              usuarioId,
                                              'rejeitado'),
                                        ),
                                      if (statusAtual != 'verificado')
                                        IconButton(
                                          icon: const Icon(Icons.check,
                                              color: Colors.greenAccent),
                                          tooltip: "Aprovar",
                                          onPressed: () => _atualizarStatusSelo(
                                              solicitacaoId,
                                              usuarioId,
                                              'verificado'),
                                        ),
                                    ],
                                  ),
                                ],
                              ),
                            ],
                          ),
                        );
                      },
                    ),
        ),
      ],
    );
  }

  Widget _buildFiltroSeloBotao(
      String titulo, String valorFiltro, Color corDestaque) {
    bool selecionado = _filtroStatusSelo == valorFiltro;
    return Expanded(
      child: ElevatedButton(
        style: ElevatedButton.styleFrom(
          backgroundColor: selecionado
              ? corDestaque.withOpacity(0.2)
              : const Color(0xFF1A2C42),
          side: BorderSide(color: selecionado ? corDestaque : Colors.white24),
          padding: const EdgeInsets.symmetric(vertical: 10),
        ),
        onPressed: () {
          setState(() {
            _filtroStatusSelo = valorFiltro;
          });
          _carregarSolicitacoesSelos();
        },
        child: Text(
          titulo,
          style: TextStyle(
            color: selecionado ? corDestaque : Colors.white70,
            fontWeight: FontWeight.bold,
            fontSize: 13,
          ),
        ),
      ),
    );
  }

  Widget _buildAbaAdministradores() {
    final bool editando = _adminEditandoId != null;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(24.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(
            editando ? "Editar Administrador" : "Cadastrar Novo Administrador",
            style: const TextStyle(
                color: Color(0xFFFF8C00),
                fontSize: 18,
                fontWeight: FontWeight.bold),
          ),
          const SizedBox(height: 12),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _nomeAdminController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: "Nome (Opcional)",
                    labelStyle: TextStyle(color: Colors.white54),
                    filled: true,
                    fillColor: Color(0xFF101B2B),
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: TextField(
                  controller: _emailAdminController,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: "E-mail do Administrador *",
                    labelStyle: TextStyle(color: Colors.white54),
                    filled: true,
                    fillColor: Color(0xFF101B2B),
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 15),
          Row(
            children: [
              Expanded(
                child: TextField(
                  controller: _cpfAdminController,
                  keyboardType: TextInputType.number,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    labelText: "CPF do Administrador",
                    labelStyle: TextStyle(color: Colors.white54),
                    filled: true,
                    fillColor: Color(0xFF101B2B),
                    border: OutlineInputBorder(),
                  ),
                ),
              ),
              const SizedBox(width: 15),
              Expanded(
                child: Row(
                  children: [
                    Expanded(
                      child: ElevatedButton(
                        style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFFF8C00),
                          padding: const EdgeInsets.symmetric(vertical: 18),
                        ),
                        onPressed: _salvarOuAtualizarAdmin,
                        child: Text(
                          editando ? "ATUALIZAR" : "CADASTRAR",
                          style: const TextStyle(
                              color: Colors.white, fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                    if (editando) ...[
                      const SizedBox(width: 10),
                      OutlinedButton(
                        style: OutlinedButton.styleFrom(
                          side: const BorderSide(color: Colors.white54),
                          padding: const EdgeInsets.symmetric(
                              vertical: 18, horizontal: 16),
                        ),
                        onPressed: _limparFormAdmin,
                        child: const Text("CANCELAR",
                            style: TextStyle(color: Colors.white70)),
                      ),
                    ],
                  ],
                ),
              ),
            ],
          ),
          const Divider(color: Colors.white24, height: 40),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                "Administradores Ativos",
                style: TextStyle(
                    color: Color(0xFFFF8C00),
                    fontSize: 18,
                    fontWeight: FontWeight.bold),
              ),
              IconButton(
                icon: const Icon(Icons.refresh, color: Color(0xFFFF8C00)),
                tooltip: "Atualizar Lista",
                onPressed: _carregarAdmins,
              ),
            ],
          ),
          const SizedBox(height: 10),
          _carregandoAdmins
              ? const Center(
                  child: Padding(
                      padding: EdgeInsets.all(20),
                      child:
                          CircularProgressIndicator(color: Color(0xFFFF8C00))))
              : _listaAdmins.isEmpty
                  ? const Padding(
                      padding: EdgeInsets.all(20),
                      child: Text("Nenhum administrador encontrado.",
                          style: TextStyle(color: Colors.white54)),
                    )
                  : ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _listaAdmins.length,
                      itemBuilder: (context, index) {
                        final admin = _listaAdmins[index];
                        return Container(
                          margin: const EdgeInsets.symmetric(vertical: 6),
                          decoration: BoxDecoration(
                            color: const Color(0xFF101B2B),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(color: Colors.white12),
                          ),
                          child: ListTile(
                            title: Text(admin['nome'] ?? 'Sem nome',
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold)),
                            subtitle: Text(
                                "E-mail: ${admin['email']} | CPF: ${admin['cpf'] ?? 'Não informado'} | Cargo: ${admin['cargo']?.toString().toUpperCase() ?? 'ATENDENTE'}",
                                style: const TextStyle(color: Colors.white70)),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                IconButton(
                                  icon: const Icon(Icons.security,
                                      color: Color(0xFFFF8C00)),
                                  tooltip: "Gerenciar Permissões",
                                  onPressed: () {
                                    Navigator.push(
                                      context,
                                      MaterialPageRoute(
                                        builder: (context) => DireitoAcessoPage(
                                          adminId: admin['id']?.toString(),
                                          adminNome:
                                              admin['nome']?.toString() ??
                                                  admin['email']?.toString(),
                                        ),
                                      ),
                                    );
                                  },
                                ),
                                IconButton(
                                  icon: const Icon(Icons.visibility,
                                      color: Color(0xFFFF8C00)),
                                  tooltip: "Visualizar",
                                  onPressed: () => _visualizarAdmin(admin),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.edit,
                                      color: Colors.cyanAccent),
                                  tooltip: "Editar",
                                  onPressed: () => _preencherParaEditar(admin),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete,
                                      color: Colors.redAccent),
                                  tooltip: "Excluir",
                                  onPressed: () => _excluirAdmin(admin),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
        ],
      ),
    );
  }

  Widget _buildAbaPremiacao() {
    final bool editandoCampanha = _campanhaEditandoId != null;

    return SingleChildScrollView(
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                editandoCampanha
                    ? 'Editar Campanha de Premiação'
                    : 'Lançar e Gerenciar Campanha de Premiação',
                style: const TextStyle(
                    color: Color(0xFFFF8C00),
                    fontSize: 18,
                    fontWeight: FontWeight.bold),
              ),
              if (editandoCampanha)
                OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.white54),
                  ),
                  onPressed: _limparFormCampanha,
                  icon:
                      const Icon(Icons.close, color: Colors.white70, size: 16),
                  label: const Text('CANCELAR EDIÇÃO',
                      style: TextStyle(color: Colors.white70, fontSize: 11)),
                ),
            ],
          ),
          const SizedBox(height: 6),
          const Text(
            'Crie ou edite campanhas definindo o prêmio, as regras, o local de abrangência e o banner.',
            style: TextStyle(color: Colors.white70, fontSize: 13),
          ),
          const SizedBox(height: 20),
          TextField(
            controller: _tituloCampanhaController,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'Título da Campanha (Ex: Concurso de Verão)',
              labelStyle: TextStyle(color: Colors.white70),
              enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white24)),
              focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFFFF8C00))),
            ),
          ),
          const SizedBox(height: 15),
          TextField(
            controller: _descricaoPremioController,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText:
                  'Descrição do Prémio / Produto ou Valor (Ex: PARAFUSADEIRA BOSCH)',
              labelStyle: TextStyle(color: Colors.white70),
              enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white24)),
              focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFFFF8C00))),
            ),
          ),
          const SizedBox(height: 15),
          TextField(
            controller: _regrasCampanhaController,
            maxLines: 5,
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              labelText: 'Regras da Campanha e Premiação',
              labelStyle: TextStyle(color: Colors.white70),
              enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white24)),
              focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFFFF8C00))),
            ),
          ),
          const SizedBox(height: 20),
          const Text(
            'Onde a campanha vai aparecer?',
            style: TextStyle(
                color: Colors.white, fontWeight: FontWeight.bold, fontSize: 14),
          ),
          const SizedBox(height: 8),
          DropdownButtonFormField<String>(
            value: _tipoAlcance,
            dropdownColor: const Color(0xFF101B2B),
            style: const TextStyle(color: Colors.white),
            decoration: const InputDecoration(
              enabledBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Colors.white24)),
              focusedBorder: OutlineInputBorder(
                  borderSide: BorderSide(color: Color(0xFFFF8C00))),
            ),
            items: const [
              DropdownMenuItem(value: 'brasil', child: Text('Brasil Inteiro')),
              DropdownMenuItem(value: 'estados', child: Text('Por Estado(s)')),
              DropdownMenuItem(
                  value: 'cidades', child: Text('Por Cidade(s) Específica(s)')),
            ],
            onChanged: (value) {
              if (value != null) {
                setState(() {
                  _tipoAlcance = value;
                });
              }
            },
          ),
          const SizedBox(height: 15),
          if (_tipoAlcance == 'estados') ...[
            const Text(
              'Selecione os Estados:',
              style: TextStyle(color: Colors.white70, fontSize: 12),
            ),
            const SizedBox(height: 8),
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                border: Border.all(color: Colors.white24),
                borderRadius: BorderRadius.circular(8),
              ),
              child: Wrap(
                spacing: 8,
                runSpacing: 4,
                children: _listaEstadosBrasil.map((uf) {
                  final selecionado = _estadosSelecionados.contains(uf);
                  return FilterChip(
                    label: Text(uf),
                    selected: selecionado,
                    selectedColor: const Color(0xFFFF8C00),
                    labelStyle: TextStyle(
                        color: selecionado ? Colors.white : Colors.white70),
                    backgroundColor: const Color(0xFF101B2B),
                    onSelected: (bool selected) {
                      setState(() {
                        if (selected) {
                          _estadosSelecionados.add(uf);
                        } else {
                          _estadosSelecionados.remove(uf);
                        }
                      });
                    },
                  );
                }).toList(),
              ),
            ),
            const SizedBox(height: 15),
          ],
          Row(
            children: [
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.white24),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: () => _selecionarDataCampanha(context, true),
                  icon: const Icon(Icons.calendar_today,
                      color: Color(0xFFFF8C00)),
                  label: Text(
                    _dataInicioCampanha == null
                        ? 'Data Início'
                        : 'Início: ${_dataInicioCampanha!.day}/${_dataInicioCampanha!.month}/${_dataInicioCampanha!.year}',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: OutlinedButton.icon(
                  style: OutlinedButton.styleFrom(
                    side: const BorderSide(color: Colors.white24),
                    padding: const EdgeInsets.symmetric(vertical: 12),
                  ),
                  onPressed: () => _selecionarDataCampanha(context, false),
                  icon: const Icon(Icons.calendar_today,
                      color: Color(0xFFFF8C00)),
                  label: Text(
                    _dataFimCampanha == null
                        ? 'Data Fim'
                        : 'Fim: ${_dataFimCampanha!.day}/${_dataFimCampanha!.month}/${_dataFimCampanha!.year}',
                    style: const TextStyle(color: Colors.white, fontSize: 12),
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 20),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFF101B2B),
              side: const BorderSide(color: Colors.white24),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: _selecionarImagemCampanha,
            icon: const Icon(Icons.image, color: Color(0xFFFF8C00)),
            label: Text(
              _imageNameCampanha != null
                  ? 'Banner selecionado: $_imageNameCampanha'
                  : _imagemUrlExistenteCampanha != null
                      ? 'Banner carregado (Clique para alterar)'
                      : 'Selecionar Banner da Campanha',
              style: const TextStyle(color: Colors.white),
            ),
          ),
          const SizedBox(height: 30),
          ElevatedButton(
            style: ElevatedButton.styleFrom(
              backgroundColor: const Color(0xFFFF8C00),
              padding: const EdgeInsets.symmetric(vertical: 14),
            ),
            onPressed: _salvandoCampanha ? null : _salvarNovaCampanha,
            child: _salvandoCampanha
                ? const SizedBox(
                    height: 20,
                    width: 20,
                    child: CircularProgressIndicator(
                        color: Colors.white, strokeWidth: 2),
                  )
                : Text(
                    editandoCampanha
                        ? 'ATUALIZAR CAMPANHA'
                        : 'Salvar e Publicar Campanha',
                    style: const TextStyle(
                        fontSize: 16,
                        color: Colors.white,
                        fontWeight: FontWeight.bold),
                  ),
          ),
          const SizedBox(height: 40),
          const Divider(color: Colors.white24),
          const SizedBox(height: 20),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text(
                'Histórico de Campanhas Salvas',
                style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold),
              ),
              IconButton(
                icon: const Icon(Icons.refresh, color: Color(0xFFFF8C00)),
                tooltip: 'Atualizar Lista',
                onPressed: _carregarCampanhas,
              ),
            ],
          ),
          const SizedBox(height: 12),
          _carregandoCampanhas
              ? const Center(
                  child: Padding(
                    padding: EdgeInsets.all(20.0),
                    child: CircularProgressIndicator(color: Color(0xFFFF8C00)),
                  ),
                )
              : _listaCampanhas.isEmpty
                  ? const Text('Nenhuma campanha salva ainda.',
                      style: TextStyle(color: Colors.white54))
                  : ListView.builder(
                      shrinkWrap: true,
                      physics: const NeverScrollableScrollPhysics(),
                      itemCount: _listaCampanhas.length,
                      itemBuilder: (context, index) {
                        final camp = _listaCampanhas[index];
                        final bool ativa = _converterBool(camp['ativa']);
                        final String titulo = camp['titulo'] ?? 'Sem Título';
                        final String premio = camp['descricao_premio'] ??
                            'Sem descrição de prêmio';

                        return Container(
                          margin: const EdgeInsets.only(bottom: 10),
                          decoration: BoxDecoration(
                            color: const Color(0xFF101B2B),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(
                                color: ativa
                                    ? const Color(0xFFFF8C00)
                                    : Colors.white12),
                          ),
                          child: ListTile(
                            title: Text(titulo,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold)),
                            subtitle: Text('Prêmio: $premio',
                                style: const TextStyle(
                                    color: Colors.white70, fontSize: 13)),
                            trailing: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Switch(
                                  value: ativa,
                                  activeColor: const Color(0xFFFF8C00),
                                  onChanged: (bool valor) =>
                                      _alternarStatusCampanha(camp, valor),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.edit,
                                      color: Colors.cyanAccent),
                                  tooltip: 'Editar Campanha',
                                  onPressed: () =>
                                      _preencherParaEditarCampanha(camp),
                                ),
                                IconButton(
                                  icon: const Icon(Icons.delete,
                                      color: Colors.redAccent),
                                  tooltip: 'Excluir Campanha',
                                  onPressed: () => _excluirCampanha(camp),
                                ),
                              ],
                            ),
                          ),
                        );
                      },
                    ),
        ],
      ),
    );
  }

  Widget _buildSecaoPlanosPorCategoria(String categoria) {
    final planosDaCategoria = _dadosPlanosPorCategoria[categoria]!;
    String catTitulo = categoria[0].toUpperCase() + categoria.substring(1);

    return ListView(
      padding: const EdgeInsets.all(20.0),
      children: [
        Text("Gerencie os planos para: $catTitulo",
            style: const TextStyle(color: Colors.white70, fontSize: 16)),
        const SizedBox(height: 20),
        for (int i = 0; i < planosDaCategoria.length; i++)
          _buildCardPlano(i + 1, categoria, planosDaCategoria[i]),
      ],
    );
  }

  Widget _buildCardPlano(
      int numeroPlano, String categoria, PlanoFormData dadosPlano) {
    return StatefulBuilder(
      builder: (context, setStateCard) {
        return Container(
          margin: const EdgeInsets.only(bottom: 25),
          padding: const EdgeInsets.all(16),
          decoration: BoxDecoration(
            color: const Color(0xFF101B2B),
            borderRadius: BorderRadius.circular(12),
            border: Border.all(color: Colors.white12),
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text("Plano $numeroPlano: ${dadosPlano.nomePlanoBase}",
                      style: const TextStyle(
                          color: Color(0xFFFF8C00),
                          fontSize: 16,
                          fontWeight: FontWeight.bold)),
                  Row(
                    children: [
                      Text(dadosPlano.ativo ? 'Ativo' : 'Inativo',
                          style: TextStyle(
                              color: dadosPlano.ativo
                                  ? Colors.greenAccent
                                  : Colors.redAccent,
                              fontSize: 12,
                              fontWeight: FontWeight.bold)),
                      Switch(
                        value: dadosPlano.ativo,
                        activeColor: const Color(0xFFFF8C00),
                        onChanged: (bool value) {
                          setStateCard(() {
                            dadosPlano.ativo = value;
                          });
                        },
                      ),
                    ],
                  ),
                ],
              ),
              const Divider(color: Colors.white12),
              const SizedBox(height: 10),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: dadosPlano.valorController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: const InputDecoration(
                        labelText: 'Valor Avulso (R\$)',
                        labelStyle:
                            TextStyle(color: Colors.white70, fontSize: 12),
                        prefixText: 'R\$ ',
                        prefixStyle:
                            TextStyle(color: Colors.white70, fontSize: 13),
                        enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: Colors.white24)),
                        focusedBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: Color(0xFFFF8C00))),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: dadosPlano.valorRecorrenteController,
                      keyboardType:
                          const TextInputType.numberWithOptions(decimal: true),
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: const InputDecoration(
                        labelText: 'Valor Recorrente (R\$)',
                        labelStyle:
                            TextStyle(color: Colors.white70, fontSize: 12),
                        prefixText: 'R\$ ',
                        prefixStyle:
                            TextStyle(color: Colors.white70, fontSize: 13),
                        enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: Colors.white24)),
                        focusedBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: Color(0xFFFF8C00))),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 15),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: dadosPlano.qtdProfissoesController,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: const InputDecoration(
                        labelText: 'Qtd Profissões / Serviços',
                        labelStyle:
                            TextStyle(color: Colors.white70, fontSize: 12),
                        enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: Colors.white24)),
                        focusedBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: Color(0xFFFF8C00))),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: dadosPlano.qtdFotosController,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: const InputDecoration(
                        labelText: 'Qtd de Fotos por Postagem',
                        labelStyle:
                            TextStyle(color: Colors.white70, fontSize: 12),
                        enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: Colors.white24)),
                        focusedBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: Color(0xFFFF8C00))),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 15),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: dadosPlano.qtdImagensIaController,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: const InputDecoration(
                        labelText: 'Qtd de Imagens da Jisa IA por Mês',
                        helperText:
                            'Limite mensal de gerações e alterações de imagens',
                        helperStyle:
                            TextStyle(color: Colors.white38, fontSize: 10),
                        labelStyle:
                            TextStyle(color: Colors.white70, fontSize: 12),
                        enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: Colors.white24)),
                        focusedBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: Color(0xFFFF8C00))),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  const Expanded(child: SizedBox()),
                ],
              ),
              const SizedBox(height: 15),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: dadosPlano.qtdVideosController,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: const InputDecoration(
                        labelText: 'Qtd de Vídeos por Postagem',
                        helperText: 'Vídeos de até 30 segundos',
                        helperStyle:
                            TextStyle(color: Colors.white38, fontSize: 10),
                        labelStyle:
                            TextStyle(color: Colors.white70, fontSize: 12),
                        enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: Colors.white24)),
                        focusedBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: Color(0xFFFF8C00))),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: dadosPlano.qtdPostagemController,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: const InputDecoration(
                        labelText: 'Qtd de Postagens de Demandas',
                        labelStyle:
                            TextStyle(color: Colors.white70, fontSize: 12),
                        enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: Colors.white24)),
                        focusedBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: Color(0xFFFF8C00))),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 15),
              Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: dadosPlano.qtdDiasController,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: const InputDecoration(
                        labelText: 'Validade Plano Avulso (dias)',
                        labelStyle:
                            TextStyle(color: Colors.white70, fontSize: 12),
                        enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: Colors.white24)),
                        focusedBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: Color(0xFFFF8C00))),
                      ),
                    ),
                  ),
                  const SizedBox(width: 10),
                  Expanded(
                    child: TextField(
                      controller: dadosPlano.qtdDiasRecorrenteController,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: Colors.white, fontSize: 13),
                      decoration: const InputDecoration(
                        labelText: 'Validade / Ciclo Recorrente (dias)',
                        labelStyle:
                            TextStyle(color: Colors.white70, fontSize: 12),
                        enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: Colors.white24)),
                        focusedBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: Color(0xFFFF8C00))),
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 15),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: const Color(0xFF1A2C42),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'Benefícios e Recursos do Plano',
                      style: TextStyle(
                        color: Color(0xFFFF8C00),
                        fontSize: 13,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(height: 14),
                    _gradeBeneficios([
                      _cartaoBeneficio(
                          titulo: 'Perfil em Destaque',
                          descricao:
                              'Exibe o perfil do usuário em posição de destaque no app.',
                          icone: Icons.workspace_premium,
                          ativo: dadosPlano.destaque,
                          aoAlterar: (v) =>
                              setStateCard(() => dadosPlano.destaque = v)),
                      _cartaoBeneficio(
                          titulo: 'Notificação por E-mail',
                          descricao:
                              'Envia notificações importantes para o e-mail do usuário.',
                          icone: Icons.mail_outline,
                          ativo: dadosPlano.notificacaoEmail,
                          aoAlterar: (v) => setStateCard(
                              () => dadosPlano.notificacaoEmail = v)),
                      _cartaoBeneficio(
                          titulo: 'Notificação Push',
                          descricao:
                              'Envia notificações pelo app no celular do usuário.',
                          icone: Icons.notifications_none,
                          ativo: dadosPlano.notificacaoPush,
                          aoAlterar: (v) => setStateCard(
                              () => dadosPlano.notificacaoPush = v)),
                      _cartaoBeneficio(
                          titulo: 'Link Facebook',
                          descricao:
                              'Exibe o link do Facebook no perfil público do usuário.',
                          icone: Icons.facebook,
                          ativo: dadosPlano.linkFacebook,
                          corIcone: const Color(0xFF669CFF),
                          aoAlterar: (v) =>
                              setStateCard(() => dadosPlano.linkFacebook = v)),
                      _cartaoBeneficio(
                          titulo: 'Link Instagram',
                          descricao:
                              'Exibe o link do Instagram no perfil público do usuário.',
                          icone: Icons.camera_alt_outlined,
                          ativo: dadosPlano.linkInstagram,
                          corIcone: const Color(0xFFE879C8),
                          aoAlterar: (v) =>
                              setStateCard(() => dadosPlano.linkInstagram = v)),
                    ]),
                  ],
                ),
              ),
              const SizedBox(height: 15),
              Align(
                alignment: Alignment.centerRight,
                child: ElevatedButton(
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF8C00),
                    padding: const EdgeInsets.symmetric(
                        horizontal: 20, vertical: 12),
                  ),
                  onPressed: () =>
                      _salvarPlanoIndividual(categoria, dadosPlano),
                  child: Text(
                    'Salvar Plano ${dadosPlano.nomePlanoBase}',
                    style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}

// Indicadores dos grupos de automações push; os controles e a persistência
// continuam centralizados em NotificacoesPushPage.

// =============================================================================
// MODERAÇÃO DE DENÚNCIAS DE PERFIS (SEM ALTERAR AS ABAS EXISTENTES)
// =============================================================================
class _PainelDenunciasPerfis extends StatefulWidget {
  final Future<void> Function(String usuarioId, String motivo)
      onBloquearUsuario;
  const _PainelDenunciasPerfis({required this.onBloquearUsuario});

  @override
  State<_PainelDenunciasPerfis> createState() => _PainelDenunciasPerfisState();
}

class _PainelDenunciasPerfisState extends State<_PainelDenunciasPerfis> {
  static const _fundo = Color(0xFF1A2C42);
  static const _cartao = Color(0xFF101B2B);
  static const _laranja = Color(0xFFFF8C00);
  final _busca = TextEditingController();
  final _observacao = TextEditingController();
  List<Map<String, dynamic>> _denuncias = [];
  Map<String, Map<String, dynamic>> _usuarios = {};
  String _filtro = 'pendente';
  bool _carregando = false;
  String? _processandoId;
  String? _erro;
  final Set<String> _expandidas = <String>{};

  @override
  void initState() {
    super.initState();
    _carregar();
  }

  @override
  void dispose() {
    _busca.dispose();
    _observacao.dispose();
    super.dispose();
  }

  String _valor(dynamic v) => v?.toString().trim() ?? '';
  String _nome(String id) {
    final u = _usuarios[id];
    final nome = _valor(u?['usuario_nome']);
    return nome.isNotEmpty
        ? nome
        : (_valor(u?['email']).isNotEmpty ? _valor(u?['email']) : id);
  }

  String _data(dynamic value) {
    final dt = DateTime.tryParse(_valor(value))?.toLocal();
    if (dt == null) return 'Data não informada';
    String dois(int n) => n.toString().padLeft(2, '0');
    return '${dois(dt.day)}/${dois(dt.month)}/${dt.year} '
        '${dois(dt.hour)}:${dois(dt.minute)}';
  }

  void _aviso(String mensagem, {bool erro = false}) {
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(SnackBar(
      content: Text(mensagem),
      backgroundColor: erro ? Colors.redAccent : Colors.green,
    ));
  }

  Future<void> _carregar() async {
    if (!mounted) return;
    setState(() {
      _carregando = true;
      _erro = null;
    });
    try {
      final client = Supabase.instance.client;
      // Apenas colunas existentes na denúncia criada pelo Feed.
      final dados = await client
          .from('tab_denuncias_perfis')
          .select('*')
          .order('created_at', ascending: false)
          .limit(500);
      final lista = List<Map<String, dynamic>>.from(dados);
      final ids = <String>{};
      for (final d in lista) {
        final denunciante = _valor(d['denunciante_id']);
        final denunciado = _valor(d['denunciado_id']);
        if (denunciante.isNotEmpty) ids.add(denunciante);
        if (denunciado.isNotEmpty) ids.add(denunciado);
      }
      final usuarios = <String, Map<String, dynamic>>{};
      if (ids.isNotEmpty) {
        // Consulta em lotes para não montar filtros PostgREST excessivos.
        final todos = ids.toList();
        for (var i = 0; i < todos.length; i += 50) {
          final fim = i + 50 < todos.length ? i + 50 : todos.length;
          final resultado = await client
              .from('tab_usuarios')
              .select('id, usuario_nome, email, usuario_tipo, usuario_status')
              .inFilter('id', todos.sublist(i, fim));
          for (final item in resultado) {
            final u = Map<String, dynamic>.from(item);
            usuarios[_valor(u['id'])] = u;
          }
        }
      }
      if (!mounted) return;
      setState(() {
        _denuncias = lista;
        _usuarios = usuarios;
      });
    } catch (e) {
      debugPrint('Erro ao carregar denúncias: $e');
      if (mounted) setState(() => _erro = e.toString());
    } finally {
      if (mounted) setState(() => _carregando = false);
    }
  }

  String _status(Map<String, dynamic> d) {
    final status = _valor(d['status']).toLowerCase();
    return status.isEmpty ? 'pendente' : status;
  }

  Future<void> _alterarStatus(
      Map<String, dynamic> denuncia, String novoStatus) async {
    final id = _valor(denuncia['id']);
    if (id.isEmpty || _processandoId != null) return;
    _observacao.text = _valor(denuncia['observacao_admin']);
    final obs = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _cartao,
        title: Text('Alterar para: ${_rotulo(novoStatus)}',
            style: const TextStyle(color: Colors.white)),
        content: TextField(
          controller: _observacao,
          maxLines: 3,
          maxLength: 1000,
          style: const TextStyle(color: Colors.white),
          decoration: const InputDecoration(
            labelText: 'Observação administrativa (opcional)',
            labelStyle: TextStyle(color: Colors.white70),
            hintText: 'Descreva o resultado da análise',
            hintStyle: TextStyle(color: Colors.white38),
            enabledBorder: OutlineInputBorder(
                borderSide: BorderSide(color: Colors.white24)),
            focusedBorder:
                OutlineInputBorder(borderSide: BorderSide(color: _laranja)),
          ),
        ),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          FilledButton(
              onPressed: () => Navigator.pop(ctx, _observacao.text.trim()),
              child: const Text('Confirmar')),
        ],
      ),
    );
    if (obs == null || !mounted) return;
    setState(() => _processandoId = id);
    try {
      final usuarioAdmin = Supabase.instance.client.auth.currentUser;
      if (usuarioAdmin == null)
        throw Exception('Sessão administrativa expirada.');
      // Campos administrativos devem existir na tabela (ver SQL complementar).
      final alteracoes = <String, dynamic>{
        'status': novoStatus,
        'observacao_admin': obs.isEmpty ? null : obs,
        'analisado_por': usuarioAdmin.id,
        'analisado_em': DateTime.now().toUtc().toIso8601String(),
      };
      final resposta = await Supabase.instance.client
          .from('tab_denuncias_perfis')
          .update(alteracoes)
          .eq('id', id)
          .select('id')
          .maybeSingle();
      if (resposta == null) {
        throw Exception(
            'Atualização não confirmada. Confira as permissões RLS.');
      }
      _aviso('Denúncia atualizada com sucesso.');
      await _carregar();
    } catch (e) {
      _aviso('Erro ao atualizar denúncia: $e', erro: true);
    } finally {
      if (mounted) setState(() => _processandoId = null);
    }
  }

  Future<void> _bloquear(Map<String, dynamic> denuncia) async {
    final id = _valor(denuncia['denunciado_id']);
    if (id.isEmpty || _processandoId != null) return;
    final motivoController = TextEditingController(
      text:
          'Bloqueio administrativo após análise da denúncia ${_valor(denuncia['id'])}: '
          '${_valor(denuncia['motivo'])}',
    );
    final motivo = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        backgroundColor: _cartao,
        title: const Text('Bloquear perfil denunciado?',
            style: TextStyle(color: Colors.white)),
        content: Column(mainAxisSize: MainAxisSize.min, children: [
          Text('Usuário: ${_nome(id)}',
              style: const TextStyle(color: Colors.white70)),
          const SizedBox(height: 12),
          TextField(
              controller: motivoController,
              maxLines: 3,
              style: const TextStyle(color: Colors.white),
              decoration: const InputDecoration(
                labelText: 'Motivo obrigatório',
                labelStyle: TextStyle(color: Colors.white70),
                border: OutlineInputBorder(),
              )),
        ]),
        actions: [
          TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('Cancelar')),
          FilledButton(
            style: FilledButton.styleFrom(backgroundColor: Colors.redAccent),
            onPressed: () {
              if (motivoController.text.trim().isEmpty) return;
              Navigator.pop(ctx, motivoController.text.trim());
            },
            child: const Text('Confirmar bloqueio'),
          ),
        ],
      ),
    );
    // Não descartar o controller enquanto o diálogo estiver em transição.
    WidgetsBinding.instance
        .addPostFrameCallback((_) => motivoController.dispose());
    if (motivo == null || !mounted) return;
    if (Supabase.instance.client.auth.currentUser?.id == id) {
      _aviso('Não é permitido bloquear a própria conta.', erro: true);
      return;
    }
    setState(() => _processandoId = _valor(denuncia['id']));
    try {
      await widget.onBloquearUsuario(id, motivo);
      _aviso('Perfil bloqueado. A denúncia permanece registrada.');
      await _carregar();
    } catch (e) {
      _aviso('Não foi possível bloquear o perfil: $e', erro: true);
    } finally {
      if (mounted) setState(() => _processandoId = null);
    }
  }

  String _rotulo(String status) {
    switch (status) {
      case 'pendente':
        return 'Pendente';
      case 'em_analise':
        return 'Em análise';
      case 'resolvida':
        return 'Resolvida';
      case 'arquivada':
        return 'Arquivada';
      default:
        return status;
    }
  }

  Widget _detalhe(String rotulo, String texto) => Padding(
        padding: const EdgeInsets.only(bottom: 8),
        child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text(rotulo,
              style: const TextStyle(color: Colors.white54, fontSize: 11)),
          const SizedBox(height: 2),
          SelectableText(texto.isEmpty ? 'Não informado' : texto,
              style: const TextStyle(color: Colors.white, fontSize: 13)),
        ]),
      );

  Color _corStatus(String status) {
    switch (status) {
      case 'pendente':
        return const Color(0xFFFFB74D);
      case 'em_analise':
        return const Color(0xFF64B5F6);
      case 'resolvida':
        return const Color(0xFF81C784);
      case 'arquivada':
        return Colors.white54;
      default:
        return Colors.white70;
    }
  }

  String _motivoLegivel(String motivo) {
    const nomes = <String, String>{
      'perfil_falso': 'Perfil falso',
      'golpe_fraude': 'Golpe ou fraude',
      'conteudo_improprio': 'Conteúdo impróprio',
      'assedio': 'Assédio',
      'informacoes_falsas': 'Informações falsas',
      'spam': 'Spam',
      'outro': 'Outro motivo',
    };
    return nomes[motivo] ?? motivo;
  }

  Widget _resumoIndicador(
      String titulo, int numero, IconData icone, Color cor) {
    return Container(
      constraints: const BoxConstraints(minWidth: 142),
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: _cartao,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icone, color: cor, size: 22),
        const SizedBox(width: 11),
        Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
          Text('$numero',
              style: const TextStyle(
                  color: Colors.white,
                  fontSize: 21,
                  fontWeight: FontWeight.bold)),
          Text(titulo,
              style: const TextStyle(color: Colors.white60, fontSize: 11)),
        ]),
      ]),
    );
  }

  Widget _cartaoDenuncia(Map<String, dynamic> d) {
    final id = _valor(d['id']);
    final denunciante = _valor(d['denunciante_id']);
    final denunciado = _valor(d['denunciado_id']);
    final status = _status(d);
    final expandida = _expandidas.contains(id);
    final ocupado = _processandoId != null;
    final statusConta = _valor(_usuarios[denunciado]?['usuario_status']);
    return Container(
      margin: const EdgeInsets.only(bottom: 9),
      decoration: BoxDecoration(
        color: _cartao,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
            color: expandida ? _laranja.withOpacity(.45) : Colors.white12),
      ),
      child: Column(children: [
        InkWell(
          borderRadius: BorderRadius.circular(12),
          onTap: () => setState(() {
            if (expandida) {
              _expandidas.remove(id);
            } else {
              _expandidas.add(id);
            }
          }),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 15, vertical: 13),
            child: Row(children: [
              Container(
                  width: 38,
                  height: 38,
                  decoration: BoxDecoration(
                      color: _laranja.withOpacity(.12),
                      borderRadius: BorderRadius.circular(9)),
                  child: const Icon(Icons.flag_outlined,
                      color: _laranja, size: 21)),
              const SizedBox(width: 12),
              Expanded(
                  child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                    Text(_nome(denunciado),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.w700,
                            fontSize: 14)),
                    const SizedBox(height: 4),
                    Text(
                        '${_motivoLegivel(_valor(d['motivo']))}  •  ${_data(d['created_at'])}',
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(
                            color: Colors.white60, fontSize: 12)),
                  ])),
              const SizedBox(width: 8),
              Container(
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                  decoration: BoxDecoration(
                      color: _corStatus(status).withOpacity(.12),
                      borderRadius: BorderRadius.circular(20),
                      border: Border.all(
                          color: _corStatus(status).withOpacity(.45))),
                  child: Text(_rotulo(status),
                      style: TextStyle(
                          color: _corStatus(status),
                          fontSize: 11,
                          fontWeight: FontWeight.w600))),
              const SizedBox(width: 8),
              Icon(
                  expandida
                      ? Icons.keyboard_arrow_up
                      : Icons.keyboard_arrow_down,
                  color: Colors.white60),
            ]),
          ),
        ),
        if (expandida) ...[
          const Divider(height: 1, color: Colors.white12),
          Padding(
              padding: const EdgeInsets.fromLTRB(16, 14, 16, 16),
              child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    LayoutBuilder(builder: (context, constraints) {
                      final largura = constraints.maxWidth > 650
                          ? (constraints.maxWidth - 24) / 2
                          : constraints.maxWidth;
                      return Wrap(spacing: 24, runSpacing: 5, children: [
                        SizedBox(
                            width: largura,
                            child: _detalhe('Perfil denunciado',
                                '${_nome(denunciado)}\nID: $denunciado')),
                        SizedBox(
                            width: largura,
                            child: _detalhe('Denunciante',
                                '${_nome(denunciante)}\nID: $denunciante')),
                        SizedBox(
                            width: largura,
                            child: _detalhe('Situação da conta', statusConta)),
                        SizedBox(
                            width: largura,
                            child: _detalhe(
                                'Motivo', _motivoLegivel(_valor(d['motivo'])))),
                      ]);
                    }),
                    const Divider(color: Colors.white12),
                    _detalhe('Descrição enviada', _valor(d['descricao'])),
                    if (_valor(d['observacao_admin']).isNotEmpty)
                      _detalhe('Observação administrativa',
                          _valor(d['observacao_admin'])),
                    if (_valor(d['analisado_em']).isNotEmpty)
                      _detalhe('Última análise', _data(d['analisado_em'])),
                    if (_valor(d['analisado_por']).isNotEmpty)
                      _detalhe('Administrador responsável',
                          _nome(_valor(d['analisado_por']))),
                    const SizedBox(height: 8),
                    Wrap(spacing: 8, runSpacing: 8, children: [
                      if (status != 'em_analise')
                        OutlinedButton.icon(
                            onPressed: ocupado
                                ? null
                                : () => _alterarStatus(d, 'em_analise'),
                            icon:
                                const Icon(Icons.visibility_outlined, size: 18),
                            label: const Text('Em análise')),
                      if (status != 'resolvida')
                        OutlinedButton.icon(
                            onPressed: ocupado
                                ? null
                                : () => _alterarStatus(d, 'resolvida'),
                            icon: const Icon(Icons.check_circle_outline,
                                size: 18),
                            label: const Text('Resolver')),
                      if (status != 'arquivada')
                        OutlinedButton.icon(
                            onPressed: ocupado
                                ? null
                                : () => _alterarStatus(d, 'arquivada'),
                            icon: const Icon(Icons.archive_outlined, size: 18),
                            label: const Text('Arquivar')),
                      if (status != 'pendente')
                        OutlinedButton.icon(
                            onPressed: ocupado
                                ? null
                                : () => _alterarStatus(d, 'pendente'),
                            icon: const Icon(Icons.undo, size: 18),
                            label: const Text('Reabrir')),
                      OutlinedButton.icon(
                          onPressed: ocupado ||
                                  statusConta.toLowerCase() == 'bloqueado'
                              ? null
                              : () => _bloquear(d),
                          icon: const Icon(Icons.block,
                              color: Colors.redAccent, size: 18),
                          label: const Text('Bloquear perfil',
                              style: TextStyle(color: Colors.redAccent))),
                    ]),
                    if (_processandoId == id)
                      const Padding(
                          padding: EdgeInsets.only(top: 10),
                          child: LinearProgressIndicator(color: _laranja)),
                  ])),
        ],
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    final termo = _busca.text.trim().toLowerCase();
    final filtradas = _denuncias.where((d) {
      if (_filtro != 'todas' && _status(d) != _filtro) return false;
      if (termo.isEmpty) return true;
      final denunciante = _valor(d['denunciante_id']);
      final denunciado = _valor(d['denunciado_id']);
      return [
        _nome(denunciante),
        _nome(denunciado),
        denunciante,
        denunciado,
        _valor(d['motivo']),
        _valor(d['descricao']),
        _valor(d['id']),
      ].any((t) => t.toLowerCase().contains(termo));
    }).toList();
    int quantidade(String s) => _denuncias.where((d) => _status(d) == s).length;
    return Container(
      color: _fundo,
      child: Column(children: [
        Padding(
            padding: const EdgeInsets.fromLTRB(16, 16, 16, 10),
            child:
                Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
              const Text('Moderação de perfis',
                  style: TextStyle(
                      color: Colors.white,
                      fontSize: 19,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 4),
              const Text(
                  'Gerencie denúncias e ações sobre perfis da plataforma.',
                  style: TextStyle(color: Colors.white60, fontSize: 12)),
              const SizedBox(height: 14),
              Wrap(spacing: 9, runSpacing: 9, children: [
                _resumoIndicador('Recebidas', _denuncias.length,
                    Icons.inbox_outlined, _laranja),
                _resumoIndicador('Pendentes', quantidade('pendente'),
                    Icons.schedule_outlined, const Color(0xFFFFB74D)),
                _resumoIndicador('Em análise', quantidade('em_analise'),
                    Icons.manage_search_outlined, const Color(0xFF64B5F6)),
                _resumoIndicador('Resolvidas', quantidade('resolvida'),
                    Icons.task_alt_outlined, const Color(0xFF81C784)),
              ]),
              const SizedBox(height: 13),
              Wrap(
                  spacing: 10,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    SizedBox(
                        width: 290,
                        child: TextField(
                          controller: _busca,
                          onChanged: (_) => setState(() {}),
                          style: const TextStyle(color: Colors.white),
                          decoration: InputDecoration(
                            hintText: 'Buscar perfil, motivo ou ID',
                            hintStyle: const TextStyle(color: Colors.white54),
                            prefixIcon:
                                const Icon(Icons.search, color: Colors.white70),
                            filled: true,
                            fillColor: _cartao,
                            isDense: true,
                            border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(9)),
                          ),
                        )),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10),
                      decoration: BoxDecoration(
                          color: _cartao,
                          borderRadius: BorderRadius.circular(9),
                          border: Border.all(color: Colors.white24)),
                      child: DropdownButtonHideUnderline(
                          child: DropdownButton<String>(
                        value: _filtro,
                        dropdownColor: _cartao,
                        style: const TextStyle(color: Colors.white),
                        items: const [
                          'pendente',
                          'em_analise',
                          'resolvida',
                          'arquivada',
                          'todas'
                        ]
                            .map((v) => DropdownMenuItem(
                                value: v,
                                child: Text(v == 'todas'
                                    ? 'Todas'
                                    : v == 'em_analise'
                                        ? 'Em análise'
                                        : v == 'pendente'
                                            ? 'Pendentes'
                                            : v == 'resolvida'
                                                ? 'Resolvidas'
                                                : 'Arquivadas')))
                            .toList(),
                        onChanged: (v) =>
                            setState(() => _filtro = v ?? 'pendente'),
                      )),
                    ),
                    IconButton(
                        tooltip: 'Atualizar denúncias',
                        onPressed: _carregando ? null : _carregar,
                        icon: const Icon(Icons.refresh, color: _laranja)),
                  ]),
              if (_erro != null)
                Padding(
                    padding: const EdgeInsets.only(top: 8),
                    child: Text('Erro de atualização: $_erro',
                        style: const TextStyle(
                            color: Colors.redAccent, fontSize: 12))),
            ])),
        Expanded(
          child: _carregando && _denuncias.isEmpty
              ? const Center(child: CircularProgressIndicator(color: _laranja))
              : _erro != null && _denuncias.isEmpty
                  ? Center(
                      child: Padding(
                          padding: const EdgeInsets.all(20),
                          child: SelectableText(
                              'Falha ao carregar denúncias: $_erro',
                              style: const TextStyle(color: Colors.redAccent))))
                  : filtradas.isEmpty
                      ? const Center(
                          child: Text('Nenhuma denúncia neste filtro.',
                              style: TextStyle(color: Colors.white70)))
                      : RefreshIndicator(
                          onRefresh: _carregar,
                          child: ListView.builder(
                            padding: const EdgeInsets.fromLTRB(16, 4, 16, 24),
                            itemCount: filtradas.length,
                            itemBuilder: (_, i) =>
                                _cartaoDenuncia(filtradas[i]),
                          )),
        ),
      ]),
    );
  }
}

class _GrupoPushIndicador extends StatelessWidget {
  final String titulo;
  final IconData icone;

  const _GrupoPushIndicador(this.titulo, this.icone);

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 9),
      decoration: BoxDecoration(
        color: const Color(0xFF101B2B),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(color: const Color(0xFFFF8C00).withOpacity(0.3)),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icone, color: const Color(0xFFFF8C00), size: 18),
          const SizedBox(width: 7),
          Text(titulo,
              style: const TextStyle(color: Colors.white, fontSize: 12)),
        ],
      ),
    );
  }
}
