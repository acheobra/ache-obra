import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:firebase_messaging/firebase_messaging.dart';

class NotificacoesPushPage extends StatefulWidget {
  const NotificacoesPushPage({super.key});

  @override
  State<NotificacoesPushPage> createState() => _NotificacoesPushPageState();
}

class _NotificacoesPushPageState extends State<NotificacoesPushPage>
    with TickerProviderStateMixin {
  final _supabase = Supabase.instance.client;
  // Identificador da conta autorizada a solicitar testes individuais.
  // A Edge Function deve validar este mesmo ID no servidor.
  static const String _usuarioAutorizadoTeste =
      '4bcb04fa-f947-4dbc-87a2-ef4914b92167';
  late TabController _mainTabController;

  bool _carregando = true;
  List<Map<String, dynamic>> _automacoes = [];
  List<Map<String, dynamic>> _historicoManual = [];

  // Pesquisa das automações e retenção pelo nome.
  final _pesquisaAutomacaoCtrl = TextEditingController();
  String _pesquisaAutomacao = '';

  // Lista Fixa de Estados do Brasil em ordem alfabética crescente
  final List<String> _estadosList = [
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

  List<String> _cidadesList = [];
  String? _estadoSelecionadoManual;
  String? _cidadeSelecionadaManual;

  // Controladores do Formulário de Disparo Manual
  final _tituloManualCtrl = TextEditingController();
  final _mensagemManualCtrl = TextEditingController();
  final _imagemManualCtrl = TextEditingController();

  List<String> _categoriasSelecionadasManual = ['todos'];
  String _statusPlanoSelecionado = 'todos';
  String _deepLinkManualSel = 'feed';
  bool _agendarEnvio = false;
  DateTime? _dataAgendamento;
  TimeOfDay? _horaAgendamento;
  bool _enviandoManual = false;

  @override
  void initState() {
    super.initState();
    _mainTabController = TabController(length: 2, vsync: this);

    if (!kIsWeb) {
      _configurarFirebaseMessaging();
    }

    _carregarDados();
  }

  void _configurarFirebaseMessaging() {
    FirebaseMessaging.onMessageOpenedApp.listen((RemoteMessage message) {
      String? destino = message.data['deep_link'] ?? message.data['screen'];
      if (destino != null) {
        _navegarParaDestino(destino);
      }
    });

    FirebaseMessaging.instance
        .getInitialMessage()
        .then((RemoteMessage? message) {
      if (message != null) {
        String? destino = message.data['deep_link'] ?? message.data['screen'];
        if (destino != null) {
          WidgetsBinding.instance.addPostFrameCallback((_) {
            _navegarParaDestino(destino);
          });
        }
      }
    });
  }

  void _navegarParaDestino(String destino) {
    if (!mounted) return;
    switch (destino) {
      case 'feed':
        break;
      case 'meus_servicos':
        break;
      case 'planos':
        break;
      case 'chat':
        break;
      case 'perfil':
        break;
      case 'selo_verificacao':
        // A navegacao efetiva do push precisa existir no roteador central.
        break;
      case 'jisa':
        // O roteamento real do push deve ser tratado no navegador central
        // do aplicativo, apontando para ia_page.dart.
        break;
      default:
        debugPrint('Destino de push desconhecido: $destino');
        break;
    }
  }

  @override
  void dispose() {
    _mainTabController.dispose();
    _tituloManualCtrl.dispose();
    _mensagemManualCtrl.dispose();
    _imagemManualCtrl.dispose();
    _pesquisaAutomacaoCtrl.dispose();
    super.dispose();
  }

  Future<void> _carregarDados() async {
    setState(() => _carregando = true);
    await _garantirRegrasPadraoAutomaticas();
    await Future.wait([
      _carregarAutomacoes(),
      _carregarHistoricoManual(),
    ]);
    if (mounted) setState(() => _carregando = false);
  }

  Future<void> _garantirRegrasPadraoAutomaticas() async {
    try {
      final regrasPadrao = [
        // Selo de Verificacao: chaves alinhadas com a Edge Function
        // processar-verificacao-selo. Inativas ate validacao do backend.
        {
          'chave_identificacao': 'selo_primeira_verificacao',
          'titulo_amigavel': 'Selo: primeira verificacao',
          'ativo': false,
          'tipo_gatilho': 'tempo_vida',
          'subtipo_evento': 'selo_sem_historico',
          'titulo_push': 'Seu perfil pode ganhar mais confiança!',
          'mensagem_push':
              '{nome}, conheça o Selo de Verificação do Ache Obra e destaque a autenticidade do seu perfil.',
          'deep_link': 'selo_verificacao',
          'delay_horas': 168,
          'intervalo_dias': 15,
          'max_envios': 3,
          'filtro_tipo_usuario': 'todos',
        },
        {
          'chave_identificacao': 'selo_renovacao_vencida',
          'titulo_amigavel': 'Selo: renovacao apos vencimento',
          'ativo': false,
          'tipo_gatilho': 'tempo_vida',
          'subtipo_evento': 'selo_vencido',
          'titulo_push': 'Seu Selo de Verificação venceu',
          'mensagem_push':
              '{nome}, seu Selo de Verificação venceu. Acesse o Ache Obra para solicitar a renovação.',
          'deep_link': 'selo_verificacao',
          'delay_horas': 24,
          'intervalo_dias': 7,
          'max_envios': 4,
          'filtro_tipo_usuario': 'todos',
        },
        {
          'chave_identificacao': 'renovacao_antecipada_plano',
          'titulo_amigavel': 'Renovação Antecipada de Planos',
          'ativo': false,
          'tipo_gatilho': 'tempo_vida',
          'subtipo_evento': 'plano_proximo_vencimento',
          'titulo_push': 'Seu plano vence em breve!',
          'mensagem_push':
              'Olá {nome}, seu plano vence em {dias} dias. Renove agora para continuar aproveitando seus benefícios.',
          'deep_link': 'planos',
          'dias_antecipacao': 5,
          'delay_horas': 0,
          'intervalo_dias': 1,
          'max_envios': 3,
          'filtro_tipo_usuario': 'todos',
        },
        {
          'chave_identificacao': 'recuperacao_plano',
          'titulo_amigavel': 'Recuperação de Planos Vencidos (Anti-Churn)',
          'ativo': false,
          'tipo_gatilho': 'tempo_vida',
          'subtipo_evento': 'plano_vencido',
          'titulo_push': 'Seu plano venceu!',
          'mensagem_push':
              'Olá {nome}, renove agora seu plano e continue fechando obras.',
          'deep_link': 'planos',
          'delay_horas': 24,
          'intervalo_dias': 3,
          'max_envios': 4,
          'filtro_tipo_usuario': 'todos',
        },
        {
          'chave_identificacao': 'inativo_7dias',
          'titulo_amigavel': 'Reengajamento de Usuários Inativos',
          'ativo': false,
          'tipo_gatilho': 'tempo_vida',
          'subtipo_evento': 'inatividade',
          'titulo_push': 'Sentimos sua falta!',
          'mensagem_push':
              'Olá {nome}, há novas obras disponíveis na sua região. Volte a conferir!',
          'deep_link': 'feed',
          'dias_inatividade': 7,
          'intervalo_dias': 7,
          'max_envios': 3,
          'filtro_tipo_usuario': 'todos',
        },
        {
          'chave_identificacao': 'boas_vindas',
          'titulo_amigavel': 'Onboarding de Novos Cadastros',
          'ativo': false,
          'tipo_gatilho': 'tempo_vida',
          'subtipo_evento': 'novo_cadastro',
          'titulo_push': 'Bem-vindo ao Ache Obra!',
          'mensagem_push':
              'Olá {nome}, publique sua primeira obra ou complete seu perfil agora mesmo.',
          'deep_link': 'meus_servicos',
          'delay_horas': 2,
          'max_envios': 1,
          'filtro_tipo_usuario': 'todos',
        },
        {
          'chave_identificacao': 'sem_servicos_postados',
          'titulo_amigavel': 'Lembrete para Profissionais sem Serviços',
          'ativo': false,
          'tipo_gatilho': 'tempo_vida',
          'subtipo_evento': 'sem_servicos',
          'titulo_push': 'Divulgue seu trabalho!',
          'mensagem_push':
              'Olá {nome}, você ainda não publicou seus serviços. Cadastre agora e seja encontrado por clientes.',
          'deep_link': 'meus_servicos',
          'delay_horas': 24,
          'intervalo_dias': 7,
          'max_envios': 3,
          'filtro_tipo_usuario': 'profissional',
        },
        {
          'chave_identificacao': 'sem_postagem_servico',
          'titulo_amigavel': 'Lembrete para Usuários sem Postagem de Serviço',
          'ativo': false,
          'tipo_gatilho': 'tempo_vida',
          'subtipo_evento': 'sem_postagem',
          'titulo_push': 'Faça sua primeira postagem!',
          'mensagem_push':
              'Olá {nome}, você ainda não possui nenhuma postagem de serviço salva. Divulgue seu trabalho agora mesmo!',
          'deep_link': 'meus_servicos',
          'delay_horas': 12,
          'intervalo_dias': 5,
          'max_envios': 3,
          'filtro_tipo_usuario': 'todos',
        },
        {
          'chave_identificacao': 'nova_obra',
          'titulo_amigavel': 'Alerta de Nova Obra para Profissionais',
          'ativo': false,
          'tipo_gatilho': 'evento',
          'subtipo_evento': 'nova_obra',
          'titulo_push': 'Nova obra na sua região!',
          'mensagem_push':
              'Olá {nome}, um cliente acabou de cadastrar uma nova obra em {cidade}.',
          'deep_link': 'feed',
          'filtro_tipo_usuario': 'profissional',
        },
        {
          'chave_identificacao': 'nova_obra_cliente',
          'titulo_amigavel': 'Alerta de Nova Obra para Clientes',
          'ativo': false,
          'tipo_gatilho': 'evento',
          'subtipo_evento': 'nova_obra',
          'titulo_push': 'Novidades no Ache Obra!',
          'mensagem_push':
              'Olá {nome}, confira as novidades e oportunidades disponíveis em {cidade}.',
          'deep_link': 'feed',
          'filtro_tipo_usuario': 'cliente',
        },
        {
          'chave_identificacao': 'nova_obra_arquiteto',
          'titulo_amigavel': 'Alerta de Nova Obra para Arquitetos',
          'ativo': false,
          'tipo_gatilho': 'evento',
          'subtipo_evento': 'nova_obra',
          'titulo_push': 'Nova obra para arquitetos!',
          'mensagem_push':
              'Olá {nome}, uma nova obra foi cadastrada em {cidade}. Confira!',
          'deep_link': 'feed',
          'filtro_tipo_usuario': 'arquiteto',
        },
        {
          'chave_identificacao': 'nova_obra_engenheiro',
          'titulo_amigavel': 'Alerta de Nova Obra para Engenheiros',
          'ativo': false,
          'tipo_gatilho': 'evento',
          'subtipo_evento': 'nova_obra',
          'titulo_push': 'Nova obra para engenheiros!',
          'mensagem_push':
              'Olá {nome}, uma nova obra foi cadastrada em {cidade}. Confira!',
          'deep_link': 'feed',
          'filtro_tipo_usuario': 'engenheiro',
        },
        {
          'chave_identificacao': 'jisa_notificacoes',
          'titulo_amigavel': 'Notificações da Jisa',
          'ativo': false,
          'tipo_gatilho': 'evento',
          'subtipo_evento': 'jisa_aviso',
          'titulo_push': 'Uma mensagem da Jisa para você!',
          'mensagem_push': 'Olá {nome}, a Jisa tem uma novidade para você.',
          'deep_link': 'jisa',
          'filtro_tipo_usuario': 'todos',
        },
        {
          'chave_identificacao': 'nova_oportunidade_plano',
          'titulo_amigavel': 'Push de Novas Oportunidades dos Planos',
          'ativo': false,
          'tipo_gatilho': 'evento',
          'subtipo_evento': 'nova_demanda',
          'titulo_push': 'Nova oportunidade - Ache Obra',
          'mensagem_push':
              'Novo serviço de {servico} em {cidade}. Confira agora!',
          'deep_link': 'feed',
          'filtro_tipo_usuario': 'automatico_por_servico',
        },
        {
          'chave_identificacao': 'chat_pendente',
          'titulo_amigavel': 'Lembrete de Mensagem Não Lida no Chat',
          'ativo': false,
          'tipo_gatilho': 'evento',
          'subtipo_evento': 'chat_pendente',
          'titulo_push': 'Você tem mensagens não lidas',
          'mensagem_push':
              'Olá {nome}, há um cliente aguardando sua resposta no chat.',
          'deep_link': 'chat',
          'horas_sem_resposta': 4,
          'filtro_tipo_usuario': 'todos',
        },
      ];

      for (var regra in regrasPadrao) {
        await _supabase.from('tab_automacoes_push').upsert(
              regra,
              onConflict: 'chave_identificacao',
              ignoreDuplicates: true,
            );
      }
    } catch (e) {
      debugPrint('Erro ao garantir regras padrão automáticas: $e');
    }
  }

  Future<void> _carregarCidadesPorEstado(String estado) async {
    try {
      final response = await _supabase
          .from('tab_localidades')
          .select('municipio')
          .eq('estado', estado)
          .order('municipio', ascending: true);

      final List<String> cidades = [];
      for (var item in response) {
        if (item['municipio'] != null) {
          cidades.add(item['municipio'].toString());
        }
      }

      if (!mounted || _estadoSelecionadoManual != estado) return;
      setState(() {
        _cidadesList = cidades;
        _cidadeSelecionadaManual = null;
      });
    } catch (e) {
      debugPrint('Erro ao carregar cidades da tab_localidades: $e');
    }
  }

  Future<void> _carregarAutomacoes() async {
    try {
      final response = await _supabase
          .from('tab_automacoes_push')
          .select()
          .order('titulo_amigavel');
      if (!mounted) return;
      setState(() {
        _automacoes = List<Map<String, dynamic>>.from(response);
      });
    } catch (e) {
      debugPrint('Erro ao carregar automações: $e');
    }
  }

  Future<void> _carregarHistoricoManual() async {
    try {
      final response = await _supabase
          .from('tab_automacoes_push')
          .select()
          .eq('tipo_gatilho', 'manual')
          .order('created_at', ascending: false)
          .limit(20);
      if (!mounted) return;
      setState(() {
        _historicoManual = List<Map<String, dynamic>>.from(response);
      });
    } catch (e) {
      debugPrint('Erro ao carregar histórico manual: $e');
    }
  }

  Future<void> _atualizarStatus(String id, bool ativo) async {
    // Impede a ativação de regras ainda não validadas no backend legado.
    const chavesProtegidas = <String>{
      'nova_obra_cliente',
      'nova_obra_arquiteto',
      'nova_obra_engenheiro',
      'jisa_notificacoes',
      'nova_obra',
    };
    final indice =
        _automacoes.indexWhere((item) => item['id']?.toString() == id);
    if (indice < 0) return;
    if (ativo &&
        chavesProtegidas.contains(_automacoes[indice]['chave_identificacao'])) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text(
            'Ativação bloqueada por segurança: valide o processador de eventos no backend antes de ativar esta regra.'),
        backgroundColor: Colors.orange,
        duration: Duration(seconds: 6),
      ));
      return;
    }
    try {
      final resultado = await _supabase
          .from('tab_automacoes_push')
          .update({
            'ativo': ativo,
            'updated_at': DateTime.now().toIso8601String(),
          })
          .eq('id', id)
          .select('id, ativo')
          .maybeSingle();
      if (resultado == null || resultado['ativo'] != ativo) {
        throw Exception(
            'O banco não confirmou a atualização. Verifique as políticas RLS.');
      }
      if (!mounted) return;
      setState(() => _automacoes[indice]['ativo'] = ativo);
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Status salvo e confirmado no banco de dados!'),
        backgroundColor: Colors.green,
      ));
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(SnackBar(
        content: Text('Erro ao atualizar status: $e'),
        backgroundColor: Colors.red,
      ));
    } finally {
      if (mounted) await _carregarAutomacoes();
    }
  }

  // Widget auxiliar para criar o seletor múltiplo customizado
  Widget _buildMultiSelectDropdown({
    required BuildContext context,
    required List<String> selectedValues,
    required Function(List<String>) onChanged,
    StateSetter? setDialogState,
  }) {
    final Map<String, String> opcoes = {
      'todos': 'Todos os Usuários',
      'arquiteto': 'Arquiteto',
      'engenheiro': 'Engenheiro',
      'profissional': 'Profissional Geral',
      'cliente': 'Cliente',
    };

    String displayText = selectedValues.contains('todos')
        ? 'Todos os Usuários'
        : selectedValues.map((e) => opcoes[e] ?? e).join(', ');

    return InkWell(
      onTap: () async {
        List<String> tempSelected = List.from(selectedValues);
        await showDialog(
          context: context,
          builder: (context) => StatefulBuilder(
            builder: (context, setModalState) => AlertDialog(
              backgroundColor: const Color(0xFF101B2B),
              shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12)),
              title: const Text('Selecionar Categorias / Público',
                  style: TextStyle(
                      color: Color(0xFFFF8C00),
                      fontSize: 16,
                      fontWeight: FontWeight.bold)),
              content: SingleChildScrollView(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: opcoes.entries.map((entry) {
                    bool isSelected = tempSelected.contains(entry.key);
                    return CheckboxListTile(
                      title: Text(entry.value,
                          style: const TextStyle(color: Colors.white)),
                      value: isSelected,
                      activeColor: const Color(0xFFFF8C00),
                      checkColor: Colors.white,
                      side: const BorderSide(color: Colors.white54),
                      onChanged: (bool? value) {
                        setModalState(() {
                          if (entry.key == 'todos') {
                            if (value == true) {
                              tempSelected = ['todos'];
                            } else {
                              tempSelected.remove('todos');
                            }
                          } else {
                            tempSelected.remove('todos');
                            if (value == true) {
                              if (!tempSelected.contains(entry.key)) {
                                tempSelected.add(entry.key);
                              }
                            } else {
                              tempSelected.remove(entry.key);
                            }
                            if (tempSelected.isEmpty) {
                              tempSelected = ['todos'];
                            }
                          }
                        });
                      },
                    );
                  }).toList(),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(context),
                  child: const Text('CANCELAR',
                      style: TextStyle(color: Colors.white70)),
                ),
                ElevatedButton(
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFFFF8C00)),
                  onPressed: () {
                    onChanged(tempSelected);
                    if (setDialogState != null) {
                      setDialogState(() {});
                    }
                    Navigator.pop(context);
                  },
                  child: const Text('OK',
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ],
            ),
          ),
        );
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 14),
        decoration: BoxDecoration(
          color: const Color(0xFF1A2C42),
          borderRadius: BorderRadius.circular(4),
          border: Border.all(color: Colors.white38),
        ),
        child: Row(
          mainAxisAlignment: MainAxisAlignment.spaceBetween,
          children: [
            Expanded(
              child: Text(
                displayText.isEmpty ? 'Selecione...' : displayText,
                style: const TextStyle(color: Colors.white, fontSize: 13),
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const Icon(Icons.arrow_drop_down, color: Colors.white70),
          ],
        ),
      ),
    );
  }

  Future<void> _dispararPushManual({bool isTeste = false}) async {
    if (_tituloManualCtrl.text.trim().isEmpty ||
        _mensagemManualCtrl.text.trim().isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Preencha pelo menos o Título e a Mensagem!'),
            backgroundColor: Colors.orange),
      );
      return;
    }

    // Evita campanhas agendadas sem data/hora válida ou no passado.
    DateTime? agendamentoLocal;
    if (!isTeste && _agendarEnvio) {
      if (_dataAgendamento == null || _horaAgendamento == null) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('Selecione a data e a hora antes de agendar.'),
          backgroundColor: Colors.orange,
        ));
        return;
      }
      agendamentoLocal = DateTime(
        _dataAgendamento!.year,
        _dataAgendamento!.month,
        _dataAgendamento!.day,
        _horaAgendamento!.hour,
        _horaAgendamento!.minute,
      );
      if (!agendamentoLocal.isAfter(DateTime.now())) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text('O agendamento deve ser para uma data e hora futuras.'),
          backgroundColor: Colors.orange,
        ));
        return;
      }
    }

    // Disparos reais podem alcançar muitos usuários: confirmação explícita.
    if (!isTeste) {
      final confirmado = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => AlertDialog(
          backgroundColor: const Color(0xFF101B2B),
          title: Text(
              _agendarEnvio ? 'Confirmar agendamento' : 'Confirmar campanha',
              style: const TextStyle(color: Color(0xFFFF8C00))),
          content: Text(
            _agendarEnvio
                ? 'Deseja agendar esta campanha para os filtros selecionados?'
                : 'Deseja colocar esta campanha na fila de envio para os filtros selecionados? Esta ação pode atingir muitos usuários.',
            style: const TextStyle(color: Colors.white70),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, false),
              child: const Text('CANCELAR'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogContext, true),
              child: const Text('CONFIRMAR',
                  style: TextStyle(color: Color(0xFFFF8C00))),
            ),
          ],
        ),
      );
      if (!mounted || confirmado != true) return;
    }

    if (_enviandoManual) return;
    setState(() => _enviandoManual = true);

    try {
      // O teste é individual e NUNCA entra na fila de campanhas.
      if (isTeste) {
        final usuario = _supabase.auth.currentUser;
        if (usuario == null) {
          throw Exception('Faça login para enviar o teste.');
        }
        if (usuario.id != _usuarioAutorizadoTeste) {
          throw Exception('Esta conta não está autorizada a enviar testes.');
        }
        final resposta = await _supabase.functions.invoke(
          'enviar-push-teste',
          body: {
            'titulo': _tituloManualCtrl.text.trim(),
            'mensagem': _mensagemManualCtrl.text.trim(),
            'deep_link': _deepLinkManualSel,
          },
        );
        final dados = resposta.data;
        if (resposta.status < 200 ||
            resposta.status >= 300 ||
            dados is! Map ||
            dados['success'] != true) {
          throw Exception('Falha no envio individual: $dados');
        }
        if (!mounted) return;
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Push de teste enviado somente para sua conta.'),
            backgroundColor: Colors.green,
          ),
        );
        return;
      }

      final String catStr = _categoriasSelecionadasManual.contains('todos')
          ? 'todos'
          : _categoriasSelecionadasManual.join(',');

      final payload = {
        'chave_identificacao':
            'manual_${DateTime.now().millisecondsSinceEpoch}',
        'titulo_amigavel':
            'Disparo Manual - ${DateTime.now().toLocal().toString().substring(0, 16)}',
        'ativo': true,
        'tipo_gatilho': 'manual',
        'titulo_push': _tituloManualCtrl.text.trim(),
        'mensagem_push': _mensagemManualCtrl.text.trim(),
        'deep_link': _deepLinkManualSel,
        'filtro_tipo_usuario': catStr,
        'filtro_status_plano': _statusPlanoSelecionado,
        'filtro_estado': _estadoSelecionadoManual,
        'filtro_cidade': _cidadeSelecionadaManual,
        // ISO UTC com fuso explícito, sem ambiguidade no backend.
        'agendar_para': agendamentoLocal?.toUtc().toIso8601String(),
      };

      final inseridos = await _supabase
          .from('tab_automacoes_push')
          .insert(payload)
          .select('id');
      if (inseridos.isEmpty) {
        throw Exception('O banco não confirmou o registro da campanha.');
      }

      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(isTeste
              ? 'Push de teste disparado para o seu usuário!'
              : (_agendarEnvio
                  ? 'Push agendado com sucesso!'
                  : 'Campanha disparada para a fila de envio!')),
          backgroundColor: Colors.green,
        ),
      );

      if (!isTeste) {
        _tituloManualCtrl.clear();
        _mensagemManualCtrl.clear();
        _imagemManualCtrl.clear();
        setState(() {
          _categoriasSelecionadasManual = ['todos'];
          _estadoSelecionadoManual = null;
          _cidadeSelecionadaManual = null;
          _cidadesList = [];
          _agendarEnvio = false;
          _dataAgendamento = null;
          _horaAgendamento = null;
        });
      }

      await _carregarHistoricoManual();
    } catch (e) {
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
            content: Text('Erro ao enviar push manual: $e'),
            backgroundColor: Colors.red),
      );
    } finally {
      if (mounted) setState(() => _enviandoManual = false);
    }
  }

  void _abrirModalEdicao(Map<String, dynamic> item) {
    final bool isNovaOportunidade =
        item['chave_identificacao'] == 'nova_oportunidade_plano';
    final bool isRenovacaoAntecipada =
        item['chave_identificacao'] == 'renovacao_antecipada_plano';

    final tituloCtrl = TextEditingController(text: item['titulo_push'] ?? '');
    final msgCtrl = TextEditingController(text: item['mensagem_push'] ?? '');
    final delayCtrl =
        TextEditingController(text: item['delay_horas']?.toString() ?? '0');
    final intervaloCtrl =
        TextEditingController(text: item['intervalo_dias']?.toString() ?? '0');
    final maxEnviosCtrl =
        TextEditingController(text: item['max_envios']?.toString() ?? '1');
    final diasAntecipacaoCtrl = TextEditingController(
        text: item['dias_antecipacao']?.toString() ?? '5');
    String deepLinkSel = item['deep_link'] ?? 'feed';

    String rawCat = item['filtro_tipo_usuario'] ?? 'todos';
    List<String> categoriaSelList =
        rawCat == 'todos' ? ['todos'] : rawCat.split(',');

    showDialog(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setDialogState) => AlertDialog(
          backgroundColor: const Color(0xFF101B2B),
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
          title: Text(
            'Editar: ${item['titulo_amigavel']}',
            style: const TextStyle(
                color: Color(0xFFFF8C00),
                fontWeight: FontWeight.bold,
                fontSize: 16),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                if (isNovaOportunidade) ...[
                  Container(
                    width: double.infinity,
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      color: const Color(0xFF1A2C42),
                      borderRadius: BorderRadius.circular(8),
                      border: Border.all(color: const Color(0xFFFF8C00)),
                    ),
                    child: const Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            Icon(Icons.auto_awesome,
                                color: Color(0xFFFF8C00), size: 18),
                            SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'Regras automáticas desta notificação',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 13,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                        SizedBox(height: 8),
                        Text(
                          '• Disparo imediato quando uma nova demanda for cadastrada.\n'
                          '• Somente usuários da mesma cidade da demanda.\n'
                          '• O serviço publicado precisa existir em tab_profissoes para o usuário.\n'
                          '• O plano atual precisa ter Notificação Push habilitada.\n'
                          '• O próprio usuário precisa manter o recebimento de Push ativado.\n'
                          '• O autor da demanda não recebe a própria notificação.',
                          style: TextStyle(
                              color: Colors.white70, fontSize: 11, height: 1.4),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(height: 14),
                ],
                const Text('Título da Notificação Push',
                    style: TextStyle(color: Colors.white70, fontSize: 12)),
                const SizedBox(height: 4),
                TextField(
                  controller: tituloCtrl,
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    filled: true,
                    fillColor: Color(0xFF1A2C42),
                    border: OutlineInputBorder(),
                  ),
                ),
                const SizedBox(height: 12),
                Text(
                  isNovaOportunidade
                      ? 'Mensagem (use {nome}, {servico} e {cidade})'
                      : 'Mensagem (use {nome}, {cidade} ou {servico})',
                  style: const TextStyle(color: Colors.white70, fontSize: 12),
                ),
                const SizedBox(height: 4),
                TextField(
                  controller: msgCtrl,
                  maxLines: 3,
                  style: const TextStyle(color: Colors.white),
                  decoration: InputDecoration(
                    filled: true,
                    fillColor: const Color(0xFF1A2C42),
                    border: const OutlineInputBorder(),
                    helperText: isNovaOportunidade
                        ? 'Ex.: Novo serviço de {servico} em {cidade}. Confira agora!'
                        : null,
                    helperStyle:
                        const TextStyle(color: Colors.white38, fontSize: 10),
                  ),
                ),
                const SizedBox(height: 12),
                if (!isNovaOportunidade) ...[
                  const Text('Categoria / Público-Alvo',
                      style: TextStyle(color: Colors.white70, fontSize: 12)),
                  const SizedBox(height: 4),
                  _buildMultiSelectDropdown(
                    context: context,
                    selectedValues: categoriaSelList,
                    onChanged: (novaLista) {
                      categoriaSelList = novaLista;
                    },
                    setDialogState: setDialogState,
                  ),
                  const SizedBox(height: 12),
                ],
                const Text('Deep Link (Destino ao Clicar)',
                    style: TextStyle(color: Colors.white70, fontSize: 12)),
                const SizedBox(height: 4),
                DropdownButtonFormField<String>(
                  value: deepLinkSel,
                  dropdownColor: const Color(0xFF101B2B),
                  style: const TextStyle(color: Colors.white),
                  decoration: const InputDecoration(
                    filled: true,
                    fillColor: Color(0xFF1A2C42),
                    border: OutlineInputBorder(),
                  ),
                  items: const [
                    DropdownMenuItem(
                        value: 'feed', child: Text('Feed de Obras')),
                    DropdownMenuItem(
                        value: 'meus_servicos',
                        child: Text('Meus Serviços / Postagem')),
                    DropdownMenuItem(
                        value: 'planos', child: Text('Tela de Planos')),
                    DropdownMenuItem(value: 'chat', child: Text('Chat')),
                    DropdownMenuItem(value: 'perfil', child: Text('Perfil')),
                    DropdownMenuItem(value: 'jisa', child: Text('Jisa IA')),
                    DropdownMenuItem(
                        value: 'selo_verificacao',
                        child: Text('Selo de Verificação')),
                  ],
                  onChanged: (val) {
                    if (val != null) {
                      setDialogState(() => deepLinkSel = val);
                    }
                  },
                ),
                if (!isNovaOportunidade) ...[
                  if (isRenovacaoAntecipada) ...[
                    const SizedBox(height: 12),
                    const Text('Dias antes do vencimento',
                        style: TextStyle(color: Colors.white70, fontSize: 11)),
                    const SizedBox(height: 4),
                    TextField(
                      controller: diasAntecipacaoCtrl,
                      keyboardType: TextInputType.number,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        hintText: 'Ex.: 5',
                        helperText:
                            'Define quantos dias antes do vencimento a renovação antecipada começa.',
                        helperStyle:
                            TextStyle(color: Colors.white38, fontSize: 10),
                        filled: true,
                        fillColor: Color(0xFF1A2C42),
                        border: OutlineInputBorder(),
                      ),
                    ),
                  ],
                  const SizedBox(height: 12),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Atraso (Horas)',
                                style: TextStyle(
                                    color: Colors.white70, fontSize: 11)),
                            const SizedBox(height: 4),
                            TextField(
                              controller: delayCtrl,
                              keyboardType: TextInputType.number,
                              style: const TextStyle(color: Colors.white),
                              decoration: const InputDecoration(
                                filled: true,
                                fillColor: Color(0xFF1A2C42),
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Recorrência (Dias)',
                                style: TextStyle(
                                    color: Colors.white70, fontSize: 11)),
                            const SizedBox(height: 4),
                            TextField(
                              controller: intervaloCtrl,
                              keyboardType: TextInputType.number,
                              style: const TextStyle(color: Colors.white),
                              decoration: const InputDecoration(
                                filled: true,
                                fillColor: Color(0xFF1A2C42),
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Max Envios',
                                style: TextStyle(
                                    color: Colors.white70, fontSize: 11)),
                            const SizedBox(height: 4),
                            TextField(
                              controller: maxEnviosCtrl,
                              keyboardType: TextInputType.number,
                              style: const TextStyle(color: Colors.white),
                              decoration: const InputDecoration(
                                filled: true,
                                fillColor: Color(0xFF1A2C42),
                                border: OutlineInputBorder(),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ],
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context),
              child: const Text('CANCELAR',
                  style: TextStyle(color: Colors.white70)),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                  backgroundColor: const Color(0xFFFF8C00)),
              onPressed: () async {
                try {
                  final Map<String, dynamic> dadosAtualizacao = {
                    'titulo_push': tituloCtrl.text.trim(),
                    'mensagem_push': msgCtrl.text.trim(),
                    'deep_link': deepLinkSel,
                    'updated_at': DateTime.now().toIso8601String(),
                  };

                  if (!isNovaOportunidade) {
                    final String catStr = categoriaSelList.contains('todos')
                        ? 'todos'
                        : categoriaSelList.join(',');

                    dadosAtualizacao.addAll({
                      'filtro_tipo_usuario': catStr,
                      'delay_horas': int.tryParse(delayCtrl.text) ?? 0,
                      'intervalo_dias': int.tryParse(intervaloCtrl.text) ?? 0,
                      'max_envios': int.tryParse(maxEnviosCtrl.text) ?? 1,
                      if (isRenovacaoAntecipada)
                        'dias_antecipacao':
                            int.tryParse(diasAntecipacaoCtrl.text) ?? 5,
                    });
                  } else {
                    // Estes campos identificam a regra usada pela Edge Function
                    // "notifica-planos". Serviço e cidade NÃO são salvos aqui:
                    // são obtidos automaticamente no momento da nova demanda.
                    dadosAtualizacao.addAll({
                      'tipo_gatilho': 'evento',
                      'subtipo_evento': 'nova_demanda',
                      'filtro_tipo_usuario': 'automatico_por_servico',
                    });
                  }

                  await _supabase
                      .from('tab_automacoes_push')
                      .update(dadosAtualizacao)
                      .eq('id', item['id']);

                  if (mounted) {
                    Navigator.pop(context);
                    _carregarAutomacoes();
                    ScaffoldMessenger.of(context).showSnackBar(
                      const SnackBar(
                          content: Text('Regra atualizada com sucesso!'),
                          backgroundColor: Colors.green),
                    );
                  }
                } catch (e) {
                  if (mounted) {
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                          content: Text('Erro ao atualizar regra: $e'),
                          backgroundColor: Colors.red),
                    );
                  }
                }
              },
              child: const Text('SALVAR',
                  style: TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  List<Map<String, dynamic>> get _automacoesFiltradas {
    final termo = _pesquisaAutomacao.trim().toLowerCase();
    if (termo.isEmpty) return _automacoes;
    return _automacoes.where((item) {
      final titulo = (item['titulo_amigavel'] ?? '').toString().toLowerCase();
      return titulo.contains(termo);
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A2C42),
      appBar: PreferredSize(
        preferredSize: const Size.fromHeight(60),
        child: Container(
          color: const Color(0xFF101B2B),
          child: TabBar(
            controller: _mainTabController,
            labelColor: const Color(0xFFFF8C00),
            unselectedLabelColor: Colors.white70,
            indicatorColor: const Color(0xFFFF8C00),
            tabs: const [
              Tab(
                icon: Icon(Icons.bolt, size: 18),
                text: 'Automações e Retenção',
              ),
              Tab(
                icon: Icon(Icons.send, size: 18),
                text: 'Disparo Manual (Campanhas)',
              ),
            ],
          ),
        ),
      ),
      body: _carregando
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFFF8C00)))
          : TabBarView(
              controller: _mainTabController,
              children: [
                // ABA 1: AUTOMAÇÕES
                SingleChildScrollView(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'Motor de Retenção e Automação Push',
                            style: TextStyle(
                                color: Color(0xFFFF8C00),
                                fontSize: 18,
                                fontWeight: FontWeight.bold),
                          ),
                          Row(
                            children: [
                              IconButton(
                                icon: const Icon(Icons.refresh,
                                    color: Color(0xFFFF8C00)),
                                tooltip: 'Atualizar',
                                onPressed: _carregarAutomacoes,
                              ),
                            ],
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Habilite, desabilite e personalize campanhas automáticas, recorrentes e baseadas em eventos 100% pelo painel admin.',
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                      const SizedBox(height: 16),
                      TextField(
                        controller: _pesquisaAutomacaoCtrl,
                        style: const TextStyle(color: Colors.white),
                        onChanged: (valor) =>
                            setState(() => _pesquisaAutomacao = valor),
                        decoration: InputDecoration(
                          hintText: 'Pesquisar automação pelo nome...',
                          hintStyle: const TextStyle(color: Colors.white38),
                          prefixIcon: const Icon(Icons.search,
                              color: Color(0xFFFF8C00)),
                          suffixIcon: _pesquisaAutomacao.isNotEmpty
                              ? IconButton(
                                  tooltip: 'Limpar pesquisa',
                                  icon: const Icon(Icons.clear,
                                      color: Colors.white54),
                                  onPressed: () {
                                    _pesquisaAutomacaoCtrl.clear();
                                    setState(() => _pesquisaAutomacao = '');
                                  },
                                )
                              : null,
                          filled: true,
                          fillColor: const Color(0xFF101B2B),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide: const BorderSide(color: Colors.white24),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(10),
                            borderSide:
                                const BorderSide(color: Color(0xFFFF8C00)),
                          ),
                        ),
                      ),
                      const SizedBox(height: 20),
                      if (_automacoes.isEmpty)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(40.0),
                            child: Text('Nenhuma regra configurada encontrada.',
                                style: TextStyle(
                                    color: Colors.white54, fontSize: 15)),
                          ),
                        )
                      else if (_automacoesFiltradas.isEmpty)
                        const Center(
                          child: Padding(
                            padding: EdgeInsets.all(40.0),
                            child: Text(
                              'Nenhuma automação encontrada para esta pesquisa.',
                              style: TextStyle(
                                  color: Colors.white54, fontSize: 15),
                            ),
                          ),
                        )
                      else
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _automacoesFiltradas.length,
                          itemBuilder: (context, index) {
                            final item = _automacoesFiltradas[index];
                            final bool ativo = item['ativo'] == true ||
                                item['ativo'] == 1 ||
                                item['ativo'] == 'true';

                            return Container(
                              key: ValueKey(item['id'] ?? index),
                              margin: const EdgeInsets.only(bottom: 15),
                              padding: const EdgeInsets.all(16),
                              decoration: BoxDecoration(
                                color: const Color(0xFF101B2B),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                    color: ativo
                                        ? const Color(0xFFFF8C00)
                                        : Colors.white12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Expanded(
                                        child: Text(
                                          item['titulo_amigavel'] ??
                                              'Sem Título',
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 15,
                                              fontWeight: FontWeight.bold),
                                        ),
                                      ),
                                      Row(
                                        children: [
                                          Text(
                                            ativo ? 'ATIVO' : 'INATIVO',
                                            style: TextStyle(
                                              color: ativo
                                                  ? Colors.greenAccent
                                                  : Colors.redAccent,
                                              fontSize: 11,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Switch(
                                            value: ativo,
                                            activeColor:
                                                const Color(0xFFFF8C00),
                                            onChanged: (bool valor) {
                                              _atualizarStatus(
                                                  item['id'].toString(), valor);
                                            },
                                          ),
                                        ],
                                      ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    'Título Push: "${item['titulo_push'] ?? ''}"',
                                    style: const TextStyle(
                                        color: Colors.white70, fontSize: 13),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'Mensagem: "${item['mensagem_push'] ?? ''}"',
                                    style: const TextStyle(
                                        color: Colors.white60, fontSize: 12),
                                  ),
                                  const SizedBox(height: 8),
                                  Wrap(
                                    spacing: 8,
                                    runSpacing: 4,
                                    children: item['chave_identificacao'] ==
                                            'nova_oportunidade_plano'
                                        ? [
                                            const Chip(
                                              label: Text(
                                                'Disparo: imediato',
                                                style: TextStyle(
                                                    color: Colors.cyanAccent,
                                                    fontSize: 11),
                                              ),
                                              backgroundColor:
                                                  Color(0xFF1A2C42),
                                            ),
                                            const Chip(
                                              label: Text(
                                                'Serviço: perfil do usuário',
                                                style: TextStyle(
                                                    color: Colors.pinkAccent,
                                                    fontSize: 11),
                                              ),
                                              backgroundColor:
                                                  Color(0xFF1A2C42),
                                            ),
                                            const Chip(
                                              label: Text(
                                                'Cidade: mesma da demanda',
                                                style: TextStyle(
                                                    color: Colors.greenAccent,
                                                    fontSize: 11),
                                              ),
                                              backgroundColor:
                                                  Color(0xFF1A2C42),
                                            ),
                                            const Chip(
                                              label: Text(
                                                'Plano: Push habilitado',
                                                style: TextStyle(
                                                    color: Colors.orangeAccent,
                                                    fontSize: 11),
                                              ),
                                              backgroundColor:
                                                  Color(0xFF1A2C42),
                                            ),
                                            Chip(
                                              label: Text(
                                                'Destino: ${item['deep_link'] ?? 'feed'}',
                                                style: const TextStyle(
                                                    color: Colors.amberAccent,
                                                    fontSize: 11),
                                              ),
                                              backgroundColor:
                                                  const Color(0xFF1A2C42),
                                            ),
                                          ]
                                        : [
                                            Chip(
                                              label: Text(
                                                  'Gatilho: ${item['tipo_gatilho']}',
                                                  style: const TextStyle(
                                                      color: Colors.cyanAccent,
                                                      fontSize: 11)),
                                              backgroundColor:
                                                  const Color(0xFF1A2C42),
                                            ),
                                            Chip(
                                              label: Text(
                                                  'Público: ${item['filtro_tipo_usuario'] ?? 'todos'}',
                                                  style: const TextStyle(
                                                      color: Colors.pinkAccent,
                                                      fontSize: 11)),
                                              backgroundColor:
                                                  const Color(0xFF1A2C42),
                                            ),
                                            Chip(
                                              label: Text(
                                                  'Destino: ${item['deep_link']}',
                                                  style: const TextStyle(
                                                      color: Colors.amberAccent,
                                                      fontSize: 11)),
                                              backgroundColor:
                                                  const Color(0xFF1A2C42),
                                            ),
                                            if (item['chave_identificacao'] ==
                                                'renovacao_antecipada_plano')
                                              Chip(
                                                label: Text(
                                                    'Antecipação: ${item['dias_antecipacao'] ?? 5}d antes',
                                                    style: const TextStyle(
                                                        color: Colors
                                                            .lightBlueAccent,
                                                        fontSize: 11)),
                                                backgroundColor:
                                                    const Color(0xFF1A2C42),
                                              ),
                                            if ((item['intervalo_dias'] ?? 0) >
                                                0)
                                              Chip(
                                                label: Text(
                                                    'Recorrência: a cada ${item['intervalo_dias']}d',
                                                    style: const TextStyle(
                                                        color:
                                                            Colors.greenAccent,
                                                        fontSize: 11)),
                                                backgroundColor:
                                                    const Color(0xFF1A2C42),
                                              ),
                                          ],
                                  ),
                                  const SizedBox(height: 10),
                                  Align(
                                    alignment: Alignment.centerRight,
                                    child: OutlinedButton.icon(
                                      style: OutlinedButton.styleFrom(
                                        side: const BorderSide(
                                            color: Color(0xFFFF8C00)),
                                      ),
                                      onPressed: () => _abrirModalEdicao(item),
                                      icon: const Icon(Icons.edit,
                                          color: Color(0xFFFF8C00), size: 16),
                                      label: const Text(
                                          'Editar Mensagem e Regras',
                                          style: TextStyle(
                                              color: Color(0xFFFF8C00),
                                              fontSize: 12)),
                                    ),
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),

                // ABA 2: DISPARO MANUAL
                SingleChildScrollView(
                  padding: const EdgeInsets.all(24.0),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'Central de Disparo Manual de Push',
                        style: TextStyle(
                            color: Color(0xFFFF8C00),
                            fontSize: 18,
                            fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 6),
                      const Text(
                        'Envie campanhas avulsas segmentadas por categoria, status de plano e geolocalização (Brasil todo, por Estado ou por Cidade).',
                        style: TextStyle(color: Colors.white70, fontSize: 13),
                      ),
                      const SizedBox(height: 20),

                      // Formulário Principal de Envio
                      Container(
                        padding: const EdgeInsets.all(20),
                        decoration: BoxDecoration(
                          color: const Color(0xFF101B2B),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: Colors.white12),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            const Text('Título da Notificação Push',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13)),
                            const SizedBox(height: 6),
                            TextField(
                              controller: _tituloManualCtrl,
                              style: const TextStyle(color: Colors.white),
                              decoration: const InputDecoration(
                                hintText: 'Ex: Novidade imperdível no app!',
                                hintStyle: TextStyle(color: Colors.white38),
                                filled: true,
                                fillColor: Color(0xFF1A2C42),
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 14),
                            const Text(
                                'Mensagem (use {nome} se desejar personalizar)',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13)),
                            const SizedBox(height: 6),
                            TextField(
                              controller: _mensagemManualCtrl,
                              maxLines: 3,
                              style: const TextStyle(color: Colors.white),
                              decoration: const InputDecoration(
                                hintText:
                                    'Olá {nome}, confira as novas funcionalidades...',
                                hintStyle: TextStyle(color: Colors.white38),
                                filled: true,
                                fillColor: Color(0xFF1A2C42),
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 14),
                            const Text(
                                'URL da Imagem / Banner (Opcional - Rich Push)',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13)),
                            const SizedBox(height: 6),
                            TextField(
                              controller: _imagemManualCtrl,
                              style: const TextStyle(color: Colors.white),
                              decoration: const InputDecoration(
                                hintText: 'https://seusite.com/imagem.png',
                                hintStyle: TextStyle(color: Colors.white38),
                                filled: true,
                                fillColor: Color(0xFF1A2C42),
                                border: OutlineInputBorder(),
                              ),
                            ),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text('Categoria(s) de Usuário',
                                          style: TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13)),
                                      const SizedBox(height: 6),
                                      _buildMultiSelectDropdown(
                                        context: context,
                                        selectedValues:
                                            _categoriasSelecionadasManual,
                                        onChanged: (novasCategorias) {
                                          setState(() {
                                            _categoriasSelecionadasManual =
                                                novasCategorias;
                                          });
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text('Status do Plano',
                                          style: TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13)),
                                      const SizedBox(height: 6),
                                      DropdownButtonFormField<String>(
                                        value: _statusPlanoSelecionado,
                                        dropdownColor: const Color(0xFF101B2B),
                                        style: const TextStyle(
                                            color: Colors.white),
                                        decoration: const InputDecoration(
                                          filled: true,
                                          fillColor: Color(0xFF1A2C42),
                                          border: OutlineInputBorder(),
                                        ),
                                        items: const [
                                          DropdownMenuItem(
                                              value: 'todos',
                                              child: Text('Todos os Status')),
                                          DropdownMenuItem(
                                              value: 'ativo',
                                              child: Text('Plano Ativo')),
                                          DropdownMenuItem(
                                              value: 'expirado',
                                              child: Text('Plano Expirado')),
                                          DropdownMenuItem(
                                              value: 'gratuito',
                                              child: Text('Plano Gratuito')),
                                        ],
                                        onChanged: (val) => setState(() =>
                                            _statusPlanoSelecionado =
                                                val ?? 'todos'),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            Row(
                              children: [
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text('Estado (UF - Fixo)',
                                          style: TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13)),
                                      const SizedBox(height: 6),
                                      DropdownButtonFormField<String>(
                                        value: _estadoSelecionadoManual,
                                        hint: const Text(
                                            'Todos os Estados (Brasil Todo)',
                                            style: TextStyle(
                                                color: Colors.white38)),
                                        dropdownColor: const Color(0xFF101B2B),
                                        style: const TextStyle(
                                            color: Colors.white),
                                        decoration: const InputDecoration(
                                          filled: true,
                                          fillColor: Color(0xFF1A2C42),
                                          border: OutlineInputBorder(),
                                        ),
                                        items: [
                                          const DropdownMenuItem<String>(
                                            value: null,
                                            child: Text(
                                                'Todos os Estados (Brasil Todo)'),
                                          ),
                                          ..._estadosList
                                              .map((uf) => DropdownMenuItem(
                                                    value: uf,
                                                    child: Text(uf),
                                                  )),
                                        ],
                                        onChanged: (val) {
                                          setState(() {
                                            _estadoSelecionadoManual = val;
                                          });
                                          if (val != null) {
                                            _carregarCidadesPorEstado(val);
                                          } else {
                                            setState(() {
                                              _cidadesList = [];
                                              _cidadeSelecionadaManual = null;
                                            });
                                          }
                                        },
                                      ),
                                    ],
                                  ),
                                ),
                                const SizedBox(width: 16),
                                Expanded(
                                  child: Column(
                                    crossAxisAlignment:
                                        CrossAxisAlignment.start,
                                    children: [
                                      const Text('Cidade (tab_localidades)',
                                          style: TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13)),
                                      const SizedBox(height: 6),
                                      DropdownButtonFormField<String>(
                                        value: _cidadeSelecionadaManual,
                                        hint: Text(
                                            _estadoSelecionadoManual == null
                                                ? 'Selecione um Estado primeiro (ou deixe vazio)'
                                                : 'Todas as cidades do estado',
                                            style: const TextStyle(
                                                color: Colors.white38,
                                                fontSize: 12)),
                                        dropdownColor: const Color(0xFF101B2B),
                                        style: const TextStyle(
                                            color: Colors.white),
                                        decoration: const InputDecoration(
                                          filled: true,
                                          fillColor: Color(0xFF1A2C42),
                                          border: OutlineInputBorder(),
                                        ),
                                        items: [
                                          const DropdownMenuItem<String>(
                                            value: null,
                                            child: Text(
                                                'Todas as cidades do estado'),
                                          ),
                                          ..._cidadesList
                                              .map((cidade) => DropdownMenuItem(
                                                    value: cidade,
                                                    child: Text(cidade),
                                                  )),
                                        ],
                                        onChanged: (val) => setState(() =>
                                            _cidadeSelecionadaManual = val),
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 14),
                            const Text('Deep Link (Destino ao Clicar)',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold,
                                    fontSize: 13)),
                            const SizedBox(height: 6),
                            DropdownButtonFormField<String>(
                              value: _deepLinkManualSel,
                              dropdownColor: const Color(0xFF101B2B),
                              style: const TextStyle(color: Colors.white),
                              decoration: const InputDecoration(
                                filled: true,
                                fillColor: Color(0xFF1A2C42),
                                border: OutlineInputBorder(),
                              ),
                              items: const [
                                DropdownMenuItem(
                                    value: 'feed',
                                    child: Text('Feed de Obras')),
                                DropdownMenuItem(
                                    value: 'meus_servicos',
                                    child: Text('Meus Serviços / Postagem')),
                                DropdownMenuItem(
                                    value: 'planos',
                                    child: Text('Tela de Planos')),
                                DropdownMenuItem(
                                    value: 'chat', child: Text('Chat')),
                                DropdownMenuItem(
                                    value: 'perfil', child: Text('Perfil')),
                                DropdownMenuItem(
                                    value: 'jisa', child: Text('Jisa IA')),
                                DropdownMenuItem(
                                    value: 'selo_verificacao',
                                    child: Text('Selo de Verificação')),
                              ],
                              onChanged: (val) {
                                if (val != null) {
                                  setState(() => _deepLinkManualSel = val);
                                }
                              },
                            ),
                            const SizedBox(height: 14),
                            SwitchListTile(
                              title: const Text('Agendar para Data/Hora Futura',
                                  style: TextStyle(
                                      color: Colors.white, fontSize: 13)),
                              value: _agendarEnvio,
                              activeColor: const Color(0xFFFF8C00),
                              onChanged: (val) =>
                                  setState(() => _agendarEnvio = val),
                            ),
                            if (_agendarEnvio) ...[
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                        backgroundColor:
                                            const Color(0xFF1A2C42)),
                                    onPressed: () async {
                                      final picked = await showDatePicker(
                                        context: context,
                                        initialDate: DateTime.now(),
                                        firstDate: DateTime.now(),
                                        lastDate: DateTime.now()
                                            .add(const Duration(days: 365)),
                                      );
                                      if (picked != null) {
                                        setState(
                                            () => _dataAgendamento = picked);
                                      }
                                    },
                                    icon: const Icon(Icons.calendar_today,
                                        size: 16, color: Color(0xFFFF8C00)),
                                    label: Text(
                                      _dataAgendamento == null
                                          ? 'Selecionar Data'
                                          : '${_dataAgendamento!.day}/${_dataAgendamento!.month}/${_dataAgendamento!.year}',
                                      style: const TextStyle(
                                          color: Colors.white70),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  ElevatedButton.icon(
                                    style: ElevatedButton.styleFrom(
                                        backgroundColor:
                                            const Color(0xFF1A2C42)),
                                    onPressed: () async {
                                      final picked = await showTimePicker(
                                        context: context,
                                        initialTime: TimeOfDay.now(),
                                      );
                                      if (picked != null) {
                                        setState(
                                            () => _horaAgendamento = picked);
                                      }
                                    },
                                    icon: const Icon(Icons.access_time,
                                        size: 16, color: Color(0xFFFF8C00)),
                                    label: Text(
                                      _horaAgendamento == null
                                          ? 'Selecionar Hora'
                                          : _horaAgendamento!.format(context),
                                      style: const TextStyle(
                                          color: Colors.white70),
                                    ),
                                  ),
                                ],
                              ),
                            ],
                            const SizedBox(height: 24),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.end,
                              children: [
                                OutlinedButton.icon(
                                  style: OutlinedButton.styleFrom(
                                    side: const BorderSide(
                                        color: Colors.cyanAccent),
                                  ),
                                  onPressed: _enviandoManual
                                      ? null
                                      : () =>
                                          _dispararPushManual(isTeste: true),
                                  icon: const Icon(Icons.bug_report,
                                      color: Colors.cyanAccent, size: 16),
                                  label: const Text(
                                      'Enviar Teste (Meu Aparelho)',
                                      style:
                                          TextStyle(color: Colors.cyanAccent)),
                                ),
                                const SizedBox(width: 12),
                                ElevatedButton.icon(
                                  style: ElevatedButton.styleFrom(
                                      backgroundColor: const Color(0xFFFF8C00)),
                                  onPressed: _enviandoManual
                                      ? null
                                      : () =>
                                          _dispararPushManual(isTeste: false),
                                  icon: _enviandoManual
                                      ? const SizedBox(
                                          width: 16,
                                          height: 16,
                                          child: CircularProgressIndicator(
                                              color: Colors.white,
                                              strokeWidth: 2))
                                      : const Icon(Icons.send,
                                          color: Colors.white, size: 16),
                                  label: Text(
                                      _agendarEnvio
                                          ? 'Agendar Campanha'
                                          : 'Disparar Push Agora',
                                      style: const TextStyle(
                                          color: Colors.white,
                                          fontWeight: FontWeight.bold)),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 30),
                      const Text(
                        'Histórico de Disparos Manuais',
                        style: TextStyle(
                            color: Colors.white,
                            fontSize: 15,
                            fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 12),
                      if (_historicoManual.isEmpty)
                        const Text(
                          'Nenhum disparo manual recente encontrado.',
                          style: TextStyle(color: Colors.white54, fontSize: 13),
                        )
                      else
                        ListView.builder(
                          shrinkWrap: true,
                          physics: const NeverScrollableScrollPhysics(),
                          itemCount: _historicoManual.length,
                          itemBuilder: (context, index) {
                            final hist = _historicoManual[index];
                            return Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFF101B2B),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.white12),
                              ),
                              child: Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceBetween,
                                children: [
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          hist['titulo_push'] ?? '',
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13),
                                        ),
                                        const SizedBox(height: 2),
                                        Text(
                                          hist['mensagem_push'] ?? '',
                                          style: const TextStyle(
                                              color: Colors.white70,
                                              fontSize: 12),
                                        ),
                                        const SizedBox(height: 4),
                                        Text(
                                          'Filtros: Cat [${hist['filtro_tipo_usuario']}] | Plano [${hist['filtro_status_plano']}] | UF [${hist['filtro_estado'] ?? 'Brasil Todo'}] | Cidade [${hist['filtro_cidade'] ?? 'Todas'}]',
                                          style: const TextStyle(
                                              color: Colors.cyanAccent,
                                              fontSize: 10),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Column(
                                    crossAxisAlignment: CrossAxisAlignment.end,
                                    children: [
                                      Chip(
                                        label: Text(
                                          hist['ativo'] == true
                                              ? 'ATIVO'
                                              : 'INATIVO',
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 10),
                                        ),
                                        backgroundColor:
                                            const Color(0xFF1A2C42),
                                      ),
                                    ],
                                  ),
                                ],
                              ),
                            );
                          },
                        ),
                    ],
                  ),
                ),
              ],
            ),
    );
  }
}
