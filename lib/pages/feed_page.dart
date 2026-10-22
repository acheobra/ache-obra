import 'dart:io';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:video_player/video_player.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:image_picker/image_picker.dart';
import 'cliente_home_page.dart';
import 'planos_usuario_page.dart';
import 'lista_orcamentos_page.dart';
import 'lista_conversas_page.dart';
import 'chat_page.dart';
import 'suporte_email_page.dart';
import 'verificacao_selo_page.dart';
import 'faq_page.dart';
import 'ia_page.dart';
import 'ranking_campanha_page.dart';
import '../main.dart';
import '../widgets/avaliacao_modal.dart';
import '../notification_service.dart';

class FeedPage extends StatefulWidget {
  const FeedPage({super.key});

  @override
  State<FeedPage> createState() => _FeedPageState();
}

class _FeedPageState extends State<FeedPage> with WidgetsBindingObserver {
  String _filtroTipoPrincipal = 'Todos';
  String? _profissaoSelecionada;
  String? _servicoSelecionado;

  String? _filtroEstadoSelecionado;
  String? _filtroCidadeSelecionada;
  String? _filtroNomePesquisado;

  String? _userCidadeLogada;
  String? _userEstadoLogado;
  String? _userFotoUrl;

  List<String> _listaCidadesFiltro = [];
  bool _carregandoCidadesFiltro = false;

  final List<String> _listaEstados = [
    "AC",
    "AL",
    "AM",
    "AP",
    "BA",
    "CE",
    "DF",
    "ES",
    "GO",
    "MA",
    "MG",
    "MS",
    "MT",
    "PA",
    "PB",
    "PE",
    "PI",
    "PR",
    "RJ",
    "RN",
    "RO",
    "RR",
    "RS",
    "SC",
    "SE",
    "SP",
    "TO"
  ];

  late Future<List<Map<String, dynamic>>> _futureDemandas;
  String _tipoUsuarioLogado = 'cliente';
  String _nomePlanoAtivo = 'gratis';

  // Força a recriação do StreamBuilder do contador de mensagens ao retornar
  // das telas de conversas/chat, garantindo leitura atualizada do Supabase.
  int _mensagensStreamRefresh = 0;

  void _atualizarContadorMensagens() {
    if (!mounted) return;
    setState(() {
      _mensagensStreamRefresh++;
    });
  }

  // Preferência individual de notificações Push.
  // O valor real fica salvo em tab_usuarios.push_ativo.
  bool _pushAtivo = true;
  bool _alterandoPush = false;

  // Notificações internas: independentes do Firebase/Push.
  List<Map<String, dynamic>> _notificacoesInternas = [];
  int _notificacoesNaoLidas = 0;
  bool _carregandoNotificacoes = false;
  String? _erroNotificacoes;
  RealtimeChannel? _canalNotificacoes;
  Timer? _timerNotificacoes;
  String? _usuarioCanalNotificacoes;
  int _versaoConsultaNotificacoes = 0;
  final ValueNotifier<int> _mudancasNotificacoes = ValueNotifier<int>(0);

  // Controla submenus exibidos dentro da própria tela do menu.
  // null = menu principal
  // outros = Outros Serviços
  // configuracoes = Configurações
  String? _submenuMenuAberto;

  List<String> get _filtrosBase {
    List<String> filtros = [
      'Todos',
      'Nome',
      'Profissionais',
      'Arquitetos',
      'Engenheiros',
    ];
    if (_tipoUsuarioLogado.toLowerCase() != 'cliente') {
      filtros.add('Clientes');
    }
    filtros.addAll(['Serviços', 'Localização']);
    return filtros;
  }

  final List<String> _listaServicosDisponiveis = [
    'Faz Tudo',
    'Impermeabilizador',
    'Encanador (Hidráulico)',
    'Eletricista',
    'Pintor Industrial',
    'Telhadista',
    'Carpinteiro',
    'Jardineiro',
    'Vidraceiro',
    'Serralheiro',
    'Azulejista',
    'Instalador de Ar Condicionado',
    'Gesseiro',
    'Pedreiro',
    'Pintor',
    'Mestre de Obras'
  ];

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _futureDemandas = _buscarDemandas();
    _carregarTipoUsuarioLogado();
    _iniciarNotificacoesInternas();
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _timerNotificacoes?.cancel();
    final canal = _canalNotificacoes;
    if (canal != null) {
      Supabase.instance.client.removeChannel(canal);
    }
    _mudancasNotificacoes.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      _carregarTipoUsuarioLogado();
      _iniciarNotificacoesInternas();
      _buscarNotificacoesInternas();
    }
  }

  Map<String, dynamic>? _extrairDadosUsuario(dynamic raw) {
    if (raw == null) return null;
    if (raw is Map<String, dynamic>) return raw;
    if (raw is Map) return Map<String, dynamic>.from(raw);
    if (raw is List && raw.isNotEmpty) {
      final item = raw.first;
      if (item is Map) return Map<String, dynamic>.from(item);
    }
    return null;
  }

  String _abreviarNome(String nomeCompleto) {
    final partes = nomeCompleto.trim().split(RegExp(r'\s+'));
    if (partes.isEmpty) return 'Usuário';
    if (partes.length == 1) return partes.first;
    final primeiroNome = partes.first;
    final ultimoNome = partes.last;
    return '$primeiroNome ${ultimoNome[0]}.';
  }

  Future<void> _carregarTipoUsuarioLogado() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      try {
        var data = await Supabase.instance.client
            .from('tab_usuarios')
            .select()
            .eq('id', user.id)
            .maybeSingle();

        if (data == null) {
          try {
            data = await Supabase.instance.client
                .from('tab_usuarios_profissionais')
                .select()
                .eq('id', user.id)
                .maybeSingle();
          } catch (_) {}
        }

        if (data != null && mounted) {
          String t = (data['usuario_tipo'] ??
                  data['tipo'] ??
                  data['tipo_usuario'] ??
                  data['perfil'] ??
                  '')
              .toString()
              .trim()
              .toLowerCase();

          String planoAtual =
              (data['nome_plano_ativo'] ?? '').toString().trim().toLowerCase();
          if (planoAtual.isEmpty) {
            planoAtual = 'gratis';
          }

          setState(() {
            if (t.isNotEmpty && t != 'null') {
              _tipoUsuarioLogado = t;
            }
            _nomePlanoAtivo = planoAtual;
            _userCidadeLogada = data?['cidade']?.toString();
            _userEstadoLogado = data?['estado']?.toString();
            _userFotoUrl = data?['foto_url']?.toString();

            // Para usuários antigos, null é tratado como ATIVO.
            // Após rodar o SQL fornecido, a coluna também terá default true.
            final pushBanco = data?['push_ativo'];
            _pushAtivo = pushBanco == null ? true : pushBanco == true;
          });

          _carregarDemandas();
        }
      } catch (e) {
        debugPrint('Erro ao verificar perfil do usuário no drawer: $e');
      }
    }
  }

  Future<void> _alterarNotificacaoPush(
    bool habilitar,
  ) async {
    if (_alterandoPush) {
      return;
    }

    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;

    if (user == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Você precisa estar logado para alterar as notificações.',
            ),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      return;
    }

    final valorAnterior = _pushAtivo;

    if (mounted) {
      setState(() {
        _alterandoPush = true;
        _pushAtivo = habilitar;
      });
    }

    try {
      // =========================================================
      // 1. A PREFERÊNCIA DO USUÁRIO É SALVA PRIMEIRO NO SUPABASE.
      // =========================================================
      //
      // Isso faz o botão funcionar também no Flutter Web.
      // No navegador, algumas operações nativas do Firebase
      // Messaging podem não estar disponíveis/configuradas.
      //
      // Ao desativar, também limpamos o fcm_token no banco.
      // Dessa forma, seu sistema de disparos não encontrará um
      // token válido para esse usuário.
      // =========================================================

      if (habilitar) {
        await supabase.from('tab_usuarios').update({
          'push_ativo': true,
        }).eq(
          'id',
          user.id,
        );
      } else {
        await supabase.from('tab_usuarios').update({
          'push_ativo': false,
          'fcm_token': null,
        }).eq(
          'id',
          user.id,
        );
      }

      // =========================================================
      // 2. NO APP NATIVO, SINCRONIZA TAMBÉM COM FIREBASE.
      // =========================================================
      //
      // No Chrome/Web não chamamos setPushEnabled(), porque o
      // Firebase Messaging Web pode exigir configuração própria
      // (VAPID/service worker) e isso estava fazendo a operação
      // inteira retornar erro mesmo depois de o banco estar certo.
      //
      // A preferência persistida no Supabase continua sendo a
      // fonte da verdade para seu sistema de notificações.
      // =========================================================

      if (!kIsWeb) {
        try {
          final resultadoFirebase = await NotificationService.setPushEnabled(
            habilitar,
          );

          if (!resultadoFirebase) {
            debugPrint(
              'Aviso: preferência Push salva no Supabase, '
              'mas o Firebase não confirmou a alteração.',
            );
          }
        } catch (e) {
          debugPrint(
            'Aviso ao sincronizar Push com Firebase: $e',
          );
        }
      }

      // =========================================================
      // 3. CONFERE O VALOR REAL QUE FICOU NO BANCO.
      // =========================================================

      final confirmacao = await supabase
          .from('tab_usuarios')
          .select(
            'push_ativo',
          )
          .eq(
            'id',
            user.id,
          )
          .maybeSingle();

      final bool valorConfirmado = confirmacao?['push_ativo'] == true;

      if (valorConfirmado != habilitar) {
        throw Exception(
          'O Supabase não confirmou a alteração da preferência.',
        );
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _pushAtivo = valorConfirmado;
      });

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            valorConfirmado
                ? 'Notificações Push ativadas.'
                : 'Notificações Push desativadas.',
          ),
          backgroundColor: valorConfirmado ? Colors.green : Colors.orange,
          duration: const Duration(
            seconds: 3,
          ),
        ),
      );
    } catch (e) {
      debugPrint(
        'Erro ao alterar preferência de Push: $e',
      );

      if (mounted) {
        setState(() {
          _pushAtivo = valorAnterior;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Não foi possível alterar as notificações Push: $e',
            ),
            backgroundColor: Colors.redAccent,
            duration: const Duration(
              seconds: 5,
            ),
          ),
        );
      }
    } finally {
      if (mounted) {
        setState(() {
          _alterandoPush = false;
        });
      }
    }
  }

  void _carregarDemandas() {
    setState(() {
      _futureDemandas = _buscarDemandas();
    });
  }

  int _calcularCamada(Map<String, dynamic> item) {
    if (_userCidadeLogada == null || _userEstadoLogado == null) return 1;

    final dadosUsuario = _extrairDadosUsuario(item['tab_usuarios']);
    final itemCidade = (dadosUsuario?['cidade'] ?? item['cidade'])
        ?.toString()
        .trim()
        .toUpperCase();
    final itemEstado = (dadosUsuario?['estado'] ?? item['estado'])
        ?.toString()
        .trim()
        .toUpperCase();
    final userCidade = _userCidadeLogada!.trim().toUpperCase();
    final userEstado = _userEstadoLogado!.trim().toUpperCase();

    if (itemCidade != null &&
        itemCidade.isNotEmpty &&
        itemCidade == userCidade) {
      return 3;
    }
    if (itemEstado != null &&
        itemEstado.isNotEmpty &&
        itemEstado == userEstado) {
      return 2;
    }
    return 1;
  }

  String _obterPapelAutor(Map<String, dynamic>? dadosUsuario) {
    if (dadosUsuario == null) return 'CLIENTE';
    final t =
        (dadosUsuario['usuario_tipo'] ?? dadosUsuario['tipo'] ?? 'cliente')
            .toString()
            .trim()
            .toLowerCase();
    if (t.contains('arquiteto')) return 'ARQUITETO';
    if (t.contains('engenheiro')) return 'ENGENHEIRO';
    if (t.contains('profissional')) return 'PROFISSIONAL';
    return 'CLIENTE';
  }

  bool _checarUsuarioVerificado(Map<String, dynamic>? dadosUsuario) {
    if (dadosUsuario == null) return false;
    final seloData = dadosUsuario['tab_selo_verificacao'];
    if (seloData == null) return false;

    if (seloData is List && seloData.isNotEmpty) {
      final status = (seloData.first['status'] ?? '').toString().toLowerCase();
      return status == 'verificado' || status == 'aprovado';
    } else if (seloData is Map) {
      final status = (seloData['status'] ?? '').toString().toLowerCase();
      return status == 'verificado' || status == 'aprovado';
    }
    return false;
  }

  Future<Map<String, dynamic>> _buscarMediaAvaliacoes(
      String prestadorId) async {
    try {
      final response = await Supabase.instance.client
          .from('tab_avaliacoes')
          .select('nota')
          .eq('prestador_id', prestadorId);

      final list = response as List;
      if (list.isEmpty) {
        return {'media': 0.0, 'total': 0};
      }
      int soma = 0;
      for (var item in list) {
        soma += (item['nota'] as num).toInt();
      }
      double media = soma / list.length;
      return {'media': media, 'total': list.length};
    } catch (e) {
      return {'media': 0.0, 'total': 0};
    }
  }

  void _mostrarTodosComentarios(
      BuildContext context, String prestadorId, String nomePrestador) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A2C42),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return DraggableScrollableSheet(
          initialChildSize: 0.7,
          minChildSize: 0.4,
          maxChildSize: 0.9,
          expand: false,
          builder: (context, scrollController) {
            return Container(
              padding: const EdgeInsets.all(20),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Center(
                    child: Container(
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: Colors.white24,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                  ),
                  const SizedBox(height: 16),
                  Text(
                    "Comentários sobre $nomePrestador",
                    style: const TextStyle(
                      color: Color(0xFFFF8C00),
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  const SizedBox(height: 8),
                  const Divider(color: Colors.white24),
                  const SizedBox(height: 10),
                  Expanded(
                    child: FutureBuilder<List<Map<String, dynamic>>>(
                      future: Supabase.instance.client
                          .from('tab_avaliacoes')
                          .select(
                              '*, tab_usuarios!tab_avaliacoes_cliente_id_fkey(usuario_nome)')
                          .eq('prestador_id', prestadorId)
                          .order('created_at', ascending: false),
                      builder: (context, snapshot) {
                        if (snapshot.connectionState ==
                            ConnectionState.waiting) {
                          return const Center(
                            child: CircularProgressIndicator(
                                color: Color(0xFFFF8C00)),
                          );
                        }
                        if (snapshot.hasError) {
                          return Center(
                            child: Text(
                              "Erro ao carregar comentários: ${snapshot.error}",
                              style: const TextStyle(color: Colors.redAccent),
                            ),
                          );
                        }
                        final avaliacoes = snapshot.data ?? [];
                        if (avaliacoes.isEmpty) {
                          return const Center(
                            child: Text(
                              "Nenhum comentário encontrado.",
                              style: TextStyle(color: Colors.white54),
                            ),
                          );
                        }
                        return ListView.builder(
                          controller: scrollController,
                          itemCount: avaliacoes.length,
                          itemBuilder: (context, index) {
                            final av = avaliacoes[index];
                            final nota = (av['nota'] ?? 0).toString();
                            final comentario = av['comentario'] ??
                                av['texto'] ??
                                av['mensagem'] ??
                                'Sem comentário';
                            final dataStr = av['created_at'] != null
                                ? av['created_at'].toString().split('T').first
                                : '';

                            final dadosAutor =
                                _extrairDadosUsuario(av['tab_usuarios']);
                            final nomeCompleto = dadosAutor?['usuario_nome'] ??
                                dadosAutor?['nome'] ??
                                av['usuario_nome'] ??
                                av['nome'] ??
                                'Usuário';
                            final nomeAbreviado = _abreviarNome(nomeCompleto);

                            return Container(
                              margin: const EdgeInsets.symmetric(vertical: 6),
                              padding: const EdgeInsets.all(12),
                              decoration: BoxDecoration(
                                color: const Color(0xFF253c59),
                                borderRadius: BorderRadius.circular(8),
                                border: Border.all(color: Colors.white12),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Row(
                                    mainAxisAlignment:
                                        MainAxisAlignment.spaceBetween,
                                    children: [
                                      Row(
                                        children: [
                                          const Icon(Icons.star,
                                              color: Colors.amber, size: 16),
                                          const SizedBox(width: 4),
                                          Text(
                                            "$nota / 5",
                                            style: const TextStyle(
                                                color: Colors.white,
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13),
                                          ),
                                        ],
                                      ),
                                      if (dataStr.isNotEmpty)
                                        Text(
                                          dataStr,
                                          style: const TextStyle(
                                              color: Colors.white54,
                                              fontSize: 11),
                                        ),
                                    ],
                                  ),
                                  const SizedBox(height: 6),
                                  Text(
                                    nomeAbreviado,
                                    style: const TextStyle(
                                      color: Color(0xFFFF8C00),
                                      fontWeight: FontWeight.bold,
                                      fontSize: 12,
                                    ),
                                  ),
                                  const SizedBox(height: 4),
                                  Text(
                                    comentario,
                                    style: const TextStyle(
                                        color: Colors.white70, fontSize: 13),
                                  ),
                                ],
                              ),
                            );
                          },
                        );
                      },
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  Widget _buildSecaoAvaliacaoCard(String? targetUserId,
      {String nomePrestador = 'Profissional',
      bool exibirBotaoComentarios = true}) {
    if (targetUserId == null || targetUserId.isEmpty) {
      return const SizedBox.shrink();
    }

    return FutureBuilder<Map<String, dynamic>>(
      future: _buscarMediaAvaliacoes(targetUserId),
      builder: (context, snapshot) {
        double media = 0.0;
        int total = 0;
        if (snapshot.hasData) {
          media = snapshot.data!['media'] ?? 0.0;
          total = snapshot.data!['total'] ?? 0;
        }

        return Padding(
          padding: const EdgeInsets.only(top: 8),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      const Icon(Icons.star, color: Colors.amber, size: 16),
                      const SizedBox(width: 4),
                      Text(
                        total > 0
                            ? '${media.toStringAsFixed(1)} ($total)'
                            : 'Sem avaliações',
                        style: const TextStyle(
                            color: Colors.white70,
                            fontSize: 12,
                            fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  TextButton.icon(
                    onPressed: () async {
                      final atualizou = await showModalBottomSheet(
                        context: context,
                        isScrollControlled: true,
                        backgroundColor: Colors.transparent,
                        builder: (context) =>
                            AvaliacaoModal(prestadorId: targetUserId),
                      );
                      if (atualizou == true) {
                        setState(() {
                          _futureDemandas = _buscarDemandas();
                        });
                      }
                    },
                    icon: const Icon(Icons.star_rate,
                        color: Color(0xFFFF8C00), size: 16),
                    label: const Text(
                      'Avaliar',
                      style: TextStyle(
                          color: Color(0xFFFF8C00),
                          fontSize: 12,
                          fontWeight: FontWeight.bold),
                    ),
                    style: TextButton.styleFrom(
                      padding: const EdgeInsets.symmetric(
                          horizontal: 8, vertical: 2),
                      minimumSize: Size.zero,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                  ),
                ],
              ),
              if (exibirBotaoComentarios && total > 0) ...[
                const SizedBox(height: 6),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    onPressed: () {
                      _mostrarTodosComentarios(
                          context, targetUserId, nomePrestador);
                    },
                    icon: const Icon(Icons.comment,
                        color: Color(0xFFFF8C00), size: 14),
                    label: Text(
                      'Ver todos os comentários ($total)',
                      style: const TextStyle(
                        color: Color(0xFFFF8C00),
                        fontSize: 12,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    style: OutlinedButton.styleFrom(
                      side:
                          const BorderSide(color: Color(0xFFFF8C00), width: 1),
                      padding: const EdgeInsets.symmetric(vertical: 4),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(6),
                      ),
                    ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Future<void> _iniciarChat(
      Map<String, dynamic> demanda, Map<String, dynamic>? dadosUsuario) async {
    final usuarioLogado = Supabase.instance.client.auth.currentUser;
    if (usuarioLogado == null) return;

    final autorDemandaId = demanda['usuario_id'] ??
        demanda['user_id'] ??
        demanda['cliente_id'] ??
        dadosUsuario?['id'];

    if (autorDemandaId == null || autorDemandaId == usuarioLogado.id) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("Você não pode conversar com você mesmo.")),
      );
      return;
    }

    showDialog(
      context: context,
      barrierDismissible: false,
      builder: (context) => const Center(
        child: CircularProgressIndicator(color: Color(0xFFFF8C00)),
      ),
    );

    try {
      final conversas = await Supabase.instance.client
          .from('tab_conversas')
          .select('id')
          .or('and(cliente_id.eq.${usuarioLogado.id},outro_usuario_id.eq.$autorDemandaId),and(cliente_id.eq.$autorDemandaId,outro_usuario_id.eq.${usuarioLogado.id})');

      int conversaId;

      if (conversas != null && (conversas as List).isNotEmpty) {
        conversaId = conversas.first['id'];
      } else {
        final nova = await Supabase.instance.client
            .from('tab_conversas')
            .insert({
              'demanda_id': demanda['id'],
              'cliente_id': autorDemandaId,
              'outro_usuario_id': usuarioLogado.id,
            })
            .select('id')
            .single();
        conversaId = nova['id'];
      }

      if (context.mounted) Navigator.pop(context);

      if (context.mounted) {
        await Navigator.push(
          context,
          MaterialPageRoute(
            builder: (context) => ChatPage(
              conversaId: conversaId,
              tituloOutroUsuario:
                  dadosUsuario?['usuario_nome'] ?? 'Chat da Demanda',
            ),
          ),
        );

        // Ao voltar do chat, força o contador a consultar novamente o banco.
        if (mounted) {
          _atualizarContadorMensagens();
        }
      }
    } catch (e) {
      if (context.mounted) Navigator.pop(context);
      debugPrint("Erro ao abrir chat: $e");
    }
  }

  Future<Map<String, List<String>>> _buscarTodasMidiasUsuario(
      Map<String, dynamic>? dadosUsuario,
      Map<String, dynamic> demandaAtual) async {
    List<String> fotosTotais = [];
    List<String> videosTotais = [];

    if (demandaAtual['fotos_trabalhos'] is List) {
      for (var f in demandaAtual['fotos_trabalhos']) {
        if (f != null && f.toString().trim().isNotEmpty) {
          fotosTotais.add(f.toString());
        }
      }
    }
    if (demandaAtual['videos_trabalhos'] is List) {
      for (var v in demandaAtual['videos_trabalhos']) {
        if (v != null && v.toString().trim().isNotEmpty) {
          videosTotais.add(v.toString());
        }
      }
    }

    final userId = dadosUsuario?['id'] ??
        demandaAtual['usuario_id'] ??
        demandaAtual['cliente_id'] ??
        demandaAtual['user_id'];

    if (userId == null) return {'fotos': fotosTotais, 'videos': videosTotais};

    final supabase = Supabase.instance.client;

    for (String coluna in ['usuario_id', 'cliente_id', 'user_id']) {
      try {
        final response = await supabase
            .from('tab_demandas_clientes')
            .select('fotos_trabalhos, videos_trabalhos')
            .eq(coluna, userId);

        for (var item in response) {
          if (item['fotos_trabalhos'] is List) {
            for (var f in item['fotos_trabalhos']) {
              if (f != null && f.toString().trim().isNotEmpty) {
                String fStr = f.toString();
                if (!fotosTotais.contains(fStr)) fotosTotais.add(fStr);
              }
            }
          }
          if (item['videos_trabalhos'] is List) {
            for (var v in item['videos_trabalhos']) {
              if (v != null && v.toString().trim().isNotEmpty) {
                String vStr = v.toString();
                if (!videosTotais.contains(vStr)) videosTotais.add(vStr);
              }
            }
          }
        }
        break;
      } catch (_) {}
    }

    return {'fotos': fotosTotais, 'videos': videosTotais};
  }

  // ============================================================
  // MENU PRINCIPAL EM TELA DE ÍCONES
  // ============================================================

  static const Color _menuLaranja = Color(0xFFFF8C00);
  static const Color _menuFundo = Color(0xFF1A2C42);
  static const Color _menuCard = Color(0xFF253C59);

  Widget _buildMenuIconCard({
    required IconData icon,
    required String titulo,
    required String subtitulo,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Container(
          decoration: BoxDecoration(
            color: _menuCard,
            borderRadius: BorderRadius.circular(16),
            border: Border.all(
              color: Colors.white.withValues(alpha: 0.08),
              width: 1,
            ),
          ),
          padding: const EdgeInsets.symmetric(
            horizontal: 8,
            vertical: 10,
          ),
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: _menuLaranja.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(14),
                  border: Border.all(
                    color: _menuLaranja.withValues(alpha: 0.35),
                  ),
                ),
                child: Icon(
                  icon,
                  color: _menuLaranja,
                  size: 24,
                ),
              ),
              const SizedBox(height: 10),
              Text(
                titulo,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white,
                  fontSize: 11.8,
                  fontWeight: FontWeight.w700,
                  height: 1.15,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                subtitulo,
                maxLines: 2,
                overflow: TextOverflow.ellipsis,
                textAlign: TextAlign.center,
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 9.0,
                  height: 1.2,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<void> _abrirPaginaPeloMenu(
    Widget pagina,
  ) async {
    if (!mounted) return;

    // Mantém o Drawer principal aberto por baixo da página.
    // Assim, ao tocar na seta de voltar da página aberta pelo menu,
    // o usuário retorna para a tela principal de ícones.
    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => pagina,
      ),
    );

    if (!mounted) return;

    // Ao voltar de páginas abertas pelo menu (inclusive Minhas Mensagens),
    // recria o stream do badge para buscar imediatamente o estado atual.
    _atualizarContadorMensagens();

    // Ao retornar, garante que nenhum submenu pequeno fique aberto.
    if (_submenuMenuAberto != null) {
      setState(() {
        _submenuMenuAberto = null;
      });
    }
  }

  Future<void> _abrirPaginaPeloSubmenu(
    Widget pagina,
  ) async {
    if (!mounted) return;

    setState(() {
      _submenuMenuAberto = null;
    });

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => pagina,
      ),
    );

    if (!mounted) return;

    if (_submenuMenuAberto != null) {
      setState(() {
        _submenuMenuAberto = null;
      });
    }
  }

  Future<void> _abrirPlanosPeloMenu() async {
    if (!mounted) return;

    await Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => PlanosUsuarioPage(
          tipoUsuarioLogado: _tipoUsuarioLogado,
        ),
      ),
    );

    if (!mounted) return;

    _carregarTipoUsuarioLogado();

    if (_submenuMenuAberto != null) {
      setState(() {
        _submenuMenuAberto = null;
      });
    }
  }

  void _abrirSubmenuOutrosServicos() {
    if (!mounted) return;

    setState(() {
      _submenuMenuAberto = 'outros';
    });
  }

  void _abrirSubmenuConfiguracoes() {
    if (!mounted) return;

    setState(() {
      _submenuMenuAberto = 'configuracoes';
    });
  }

  void _fecharSubmenuMenu() {
    if (!mounted) return;

    setState(() {
      _submenuMenuAberto = null;
    });
  }

  Widget _buildSubmenuContainer({
    required IconData icon,
    required String titulo,
    required Widget child,
  }) {
    return Material(
      color: Colors.transparent,
      child: Container(
        width: double.infinity,
        constraints: const BoxConstraints(
          maxWidth: 520,
        ),
        margin: const EdgeInsets.symmetric(
          horizontal: 18,
        ),
        padding: const EdgeInsets.fromLTRB(
          18,
          16,
          18,
          20,
        ),
        decoration: BoxDecoration(
          color: _menuFundo,
          borderRadius: BorderRadius.circular(
            22,
          ),
          border: Border.all(
            color: _menuLaranja.withValues(
              alpha: 0.35,
            ),
            width: 1,
          ),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(
                alpha: 0.35,
              ),
              blurRadius: 20,
              offset: const Offset(
                0,
                8,
              ),
            ),
          ],
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Row(
              children: [
                Icon(
                  icon,
                  color: _menuLaranja,
                  size: 24,
                ),
                const SizedBox(
                  width: 10,
                ),
                Expanded(
                  child: Text(
                    titulo,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 18,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                IconButton(
                  tooltip: 'Fechar submenu',
                  onPressed: _fecharSubmenuMenu,
                  icon: const Icon(
                    Icons.close,
                    color: _menuLaranja,
                    size: 24,
                  ),
                ),
              ],
            ),
            const SizedBox(
              height: 14,
            ),
            child,
          ],
        ),
      ),
    );
  }

  Widget _buildSubmenuOutrosServicosOverlay() {
    return _buildSubmenuContainer(
      icon: Icons.miscellaneous_services,
      titulo: 'Outros Serviços',
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Expanded(
            child: SizedBox(
              height: 150,
              child: _buildMenuIconCard(
                icon: Icons.request_quote,
                titulo: 'Orçamento',
                subtitulo: 'Acompanhe seus orçamentos',
                onTap: () {
                  _abrirPaginaPeloSubmenu(
                    const ListaOrcamentosPage(),
                  );
                },
              ),
            ),
          ),
          const SizedBox(
            width: 12,
          ),
          Expanded(
            child: SizedBox(
              height: 150,
              child: _buildMenuIconCard(
                icon: Icons.shopping_cart_checkout,
                titulo: 'Lista de Compras',
                subtitulo: 'Veja sua lista de materiais',
                onTap: () {
                  _abrirPaginaPeloSubmenu(
                    const ClienteHomePage(
                      abaInicial: 2,
                    ),
                  );
                },
              ),
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildSubmenuConfiguracoesOverlay() {
    return _buildSubmenuContainer(
      icon: Icons.settings,
      titulo: 'Configurações',
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(
            decoration: BoxDecoration(
              color: _menuCard,
              borderRadius: BorderRadius.circular(
                16,
              ),
              border: Border.all(
                color: Colors.white.withValues(
                  alpha: 0.08,
                ),
              ),
            ),
            child: SwitchListTile(
              secondary: _alterandoPush
                  ? const SizedBox(
                      width: 22,
                      height: 22,
                      child: CircularProgressIndicator(
                        strokeWidth: 2,
                        color: _menuLaranja,
                      ),
                    )
                  : Icon(
                      _pushAtivo
                          ? Icons.notifications_active_outlined
                          : Icons.notifications_off_outlined,
                      color: _menuLaranja,
                    ),
              title: const Text(
                'Notificação Push',
                style: TextStyle(
                  color: Colors.white,
                  fontWeight: FontWeight.bold,
                ),
              ),
              subtitle: Text(
                _pushAtivo
                    ? 'Recebimento de notificações ativado'
                    : 'Recebimento de notificações desativado',
                style: const TextStyle(
                  color: Colors.white54,
                  fontSize: 11,
                ),
              ),
              value: _pushAtivo,
              activeThumbColor: _menuLaranja,
              activeTrackColor: _menuLaranja.withValues(
                alpha: 0.35,
              ),
              inactiveThumbColor: Colors.white54,
              inactiveTrackColor: Colors.white12,
              onChanged: _alterandoPush
                  ? null
                  : (valor) async {
                      await _alterarNotificacaoPush(
                        valor,
                      );
                    },
            ),
          ),
          const SizedBox(
            height: 12,
          ),
          InkWell(
            onTap: () {
              _abrirPaginaPeloSubmenu(
                const MinhaContaPage(),
              );
            },
            borderRadius: BorderRadius.circular(
              16,
            ),
            child: Container(
              width: double.infinity,
              padding: const EdgeInsets.symmetric(
                horizontal: 16,
                vertical: 15,
              ),
              decoration: BoxDecoration(
                color: _menuCard,
                borderRadius: BorderRadius.circular(
                  16,
                ),
                border: Border.all(
                  color: Colors.white.withValues(
                    alpha: 0.08,
                  ),
                ),
              ),
              child: const Row(
                children: [
                  Icon(
                    Icons.person_remove,
                    color: _menuLaranja,
                    size: 24,
                  ),
                  SizedBox(
                    width: 12,
                  ),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(
                          'Excluir Conta',
                          style: TextStyle(
                            color: Colors.redAccent,
                            fontSize: 13,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        SizedBox(
                          height: 2,
                        ),
                        Text(
                          'Desativar conta no sistema',
                          style: TextStyle(
                            color: Colors.white54,
                            fontSize: 11,
                          ),
                        ),
                      ],
                    ),
                  ),
                  Icon(
                    Icons.chevron_right,
                    color: _menuLaranja,
                  ),
                ],
              ),
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _sairDaContaPeloMenu() async {
    if (!mounted) return;

    final bool? confirmarSaida = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return AlertDialog(
          backgroundColor: _menuFundo,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(
              18,
            ),
            side: BorderSide(
              color: _menuLaranja.withValues(
                alpha: 0.45,
              ),
            ),
          ),
          title: const Row(
            children: [
              Icon(
                Icons.logout,
                color: _menuLaranja,
                size: 24,
              ),
              SizedBox(
                width: 10,
              ),
              Expanded(
                child: Text(
                  'Sair da Conta',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ],
          ),
          content: const Text(
            'Você realmente deseja sair da sua conta?',
            style: TextStyle(
              color: Colors.white70,
              fontSize: 14,
              height: 1.35,
            ),
          ),
          actionsPadding: const EdgeInsets.fromLTRB(
            16,
            0,
            16,
            14,
          ),
          actions: [
            OutlinedButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  false,
                );
              },
              style: OutlinedButton.styleFrom(
                foregroundColor: Colors.white70,
                side: const BorderSide(
                  color: Colors.white24,
                ),
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                    10,
                  ),
                ),
              ),
              child: const Text(
                'NÃO',
              ),
            ),
            ElevatedButton(
              onPressed: () {
                Navigator.pop(
                  dialogContext,
                  true,
                );
              },
              style: ElevatedButton.styleFrom(
                backgroundColor: _menuLaranja,
                foregroundColor: Colors.white,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(
                    10,
                  ),
                ),
              ),
              child: const Text(
                'SIM',
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (confirmarSaida != true || !mounted) {
      return;
    }

    // Fecha o menu principal somente após o usuário confirmar.
    Navigator.pop(
      context,
    );

    await Future.delayed(
      const Duration(
        milliseconds: 100,
      ),
    );

    await Supabase.instance.client.auth.signOut();

    if (!mounted) return;

    Navigator.of(context).pushAndRemoveUntil(
      MaterialPageRoute(
        builder: (_) => const AcheObraHome(),
      ),
      (Route<dynamic> route) => false,
    );
  }

  Widget _buildMenuPrincipalIcones(bool isProfissional) {
    return Drawer(
      width: MediaQuery.sizeOf(context).width,
      backgroundColor: _menuFundo,
      child: SafeArea(
        child: Stack(
          children: [
            Column(
              children: [
                Container(
                  padding: const EdgeInsets.fromLTRB(
                    18,
                    14,
                    12,
                    14,
                  ),
                  decoration: BoxDecoration(
                    color: _menuCard,
                    border: Border(
                      bottom: BorderSide(
                        color: Colors.white.withValues(
                          alpha: 0.08,
                        ),
                      ),
                    ),
                  ),
                  child: Row(
                    children: [
                      CircleAvatar(
                        radius: 24,
                        backgroundColor: _menuLaranja,
                        backgroundImage: (_userFotoUrl != null &&
                                _userFotoUrl!.trim().isNotEmpty)
                            ? NetworkImage(
                                _userFotoUrl!.trim(),
                              )
                            : null,
                        child: (_userFotoUrl == null ||
                                _userFotoUrl!.trim().isEmpty)
                            ? const Icon(
                                Icons.person,
                                color: Colors.white,
                                size: 24,
                              )
                            : null,
                      ),
                      const SizedBox(
                        width: 12,
                      ),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              'Menu Principal',
                              style: TextStyle(
                                color: Colors.white,
                                fontSize: 18,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            SizedBox(
                              height: 2,
                            ),
                            Text(
                              'Ache Obra',
                              style: TextStyle(
                                color: _menuLaranja,
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                              ),
                            ),
                          ],
                        ),
                      ),
                      IconButton(
                        tooltip: 'Fechar menu',
                        onPressed: () {
                          _submenuMenuAberto = null;
                          Navigator.pop(
                            context,
                          );
                        },
                        icon: const Icon(
                          Icons.close,
                          color: _menuLaranja,
                          size: 26,
                        ),
                      ),
                    ],
                  ),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      int colunas = 3;

                      if (constraints.maxWidth >= 900) {
                        colunas = 5;
                      } else if (constraints.maxWidth >= 650) {
                        colunas = 4;
                      }

                      return GridView.count(
                        padding: const EdgeInsets.all(
                          16,
                        ),
                        crossAxisCount: colunas,
                        mainAxisSpacing: 12,
                        crossAxisSpacing: 12,

                        // Mais altura no celular para impedir
                        // RenderFlex/BOTTOM OVERFLOW em títulos
                        // como "Minhas Mensagens".
                        childAspectRatio:
                            constraints.maxWidth >= 650 ? 1.02 : 0.74,
                        children: [
                          _buildMenuIconCard(
                            icon: Icons.manage_accounts,
                            titulo: 'Editar Perfil',
                            subtitulo: 'Gerencie seus dados e foto',
                            onTap: () {
                              _abrirPaginaPeloMenu(
                                const ClienteHomePage(
                                  abaInicial: 0,
                                ),
                              );
                            },
                          ),
                          _buildMenuIconCard(
                            icon: Icons.handyman,
                            titulo: isProfissional
                                ? 'Postar Serviço'
                                : 'Contratar Profissional',
                            subtitulo: isProfissional
                                ? 'Publique o seu serviço'
                                : 'Encontre o que precisa',
                            onTap: () {
                              _abrirPaginaPeloMenu(
                                const ClienteHomePage(
                                  abaInicial: 1,
                                ),
                              );
                            },
                          ),
                          _buildMenuIconCard(
                            icon: Icons.star,
                            titulo: 'Meus Planos',
                            subtitulo: 'Gerencie sua assinatura',
                            onTap: _abrirPlanosPeloMenu,
                          ),
                          _buildMenuIconCard(
                            icon: Icons.verified,
                            titulo: 'Selo de Verificação',
                            subtitulo: 'Solicite a verificação',
                            onTap: () {
                              _abrirPaginaPeloMenu(
                                const SeloVerificacaoPage(),
                              );
                            },
                          ),
                          _buildMenuIconCard(
                            icon: Icons.auto_awesome,
                            titulo: 'Jisa IA',
                            subtitulo: 'Sua assistente de construção',
                            onTap: () {
                              _abrirPaginaPeloMenu(
                                const IaPage(),
                              );
                            },
                          ),
                          _buildMenuIconCard(
                            icon: Icons.chat,
                            titulo: 'Minhas Mensagens',
                            subtitulo: 'Veja suas conversas ativas',
                            onTap: () {
                              _abrirPaginaPeloMenu(
                                const ListaConversasPage(),
                              );
                            },
                          ),
                          _buildMenuIconCard(
                            icon: Icons.miscellaneous_services,
                            titulo: 'Outros Serviços',
                            subtitulo: 'Orçamento e lista de compras',
                            onTap: _abrirSubmenuOutrosServicos,
                          ),
                          _buildMenuIconCard(
                            icon: Icons.support_agent,
                            titulo: 'Suporte',
                            subtitulo: 'Entre em contato por e-mail',
                            onTap: () {
                              _abrirPaginaPeloMenu(
                                const SuporteEmailPage(),
                              );
                            },
                          ),
                          _buildMenuIconCard(
                            icon: Icons.help_outline,
                            titulo: 'FAQ - dúvidas',
                            subtitulo: 'Perguntas e respostas',
                            onTap: () {
                              _abrirPaginaPeloMenu(
                                const FaqPage(),
                              );
                            },
                          ),
                          _buildMenuIconCard(
                            icon: Icons.settings,
                            titulo: 'Configurações',
                            subtitulo: 'Push e conta',
                            onTap: _abrirSubmenuConfiguracoes,
                          ),
                          _buildMenuIconCard(
                            icon: Icons.exit_to_app,
                            titulo: 'Sair da Conta',
                            subtitulo: 'Encerrar sessão',
                            onTap: _sairDaContaPeloMenu,
                          ),
                        ],
                      );
                    },
                  ),
                ),
              ],
            ),

            // =====================================================
            // SUBMENU NA PRÓPRIA TELA DO MENU
            // =====================================================
            if (_submenuMenuAberto != null) ...[
              Positioned.fill(
                child: GestureDetector(
                  onTap: _fecharSubmenuMenu,
                  child: Container(
                    color: Colors.black.withValues(
                      alpha: 0.55,
                    ),
                  ),
                ),
              ),
              Positioned.fill(
                child: SafeArea(
                  child: Center(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.symmetric(
                        vertical: 24,
                      ),
                      child: _submenuMenuAberto == 'outros'
                          ? _buildSubmenuOutrosServicosOverlay()
                          : _buildSubmenuConfiguracoesOverlay(),
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  // ============================================================
  // CENTRAL DE NOTIFICAÇÕES INTERNAS (separada das notificações Push)
  // ============================================================
  void _iniciarNotificacoesInternas() {
    final usuarioId = Supabase.instance.client.auth.currentUser?.id;
    if (usuarioId == _usuarioCanalNotificacoes && _timerNotificacoes != null) {
      return;
    }
    _timerNotificacoes?.cancel();
    _timerNotificacoes = null;
    final canalAnterior = _canalNotificacoes;
    _canalNotificacoes = null;
    if (canalAnterior != null) {
      Supabase.instance.client.removeChannel(canalAnterior);
    }
    _usuarioCanalNotificacoes = usuarioId;
    _versaoConsultaNotificacoes++;
    if (usuarioId == null) {
      if (mounted) {
        setState(() {
          _notificacoesInternas = [];
          _notificacoesNaoLidas = 0;
          _erroNotificacoes = null;
          _carregandoNotificacoes = false;
        });
      }
      return;
    }
    _buscarNotificacoesInternas();
    // Consulta periódica como fallback caso Realtime não esteja habilitado.
    _timerNotificacoes = Timer.periodic(
      const Duration(seconds: 45),
      (_) => _buscarNotificacoesInternas(),
    );
    _canalNotificacoes = Supabase.instance.client
        .channel('internas_feed_$usuarioId')
        .onPostgresChanges(
          event: PostgresChangeEvent.all,
          schema: 'public',
          table: 'tab_notificacoes_internas',
          filter: PostgresChangeFilter(
            type: PostgresChangeFilterType.eq,
            column: 'usuario_id',
            value: usuarioId,
          ),
          callback: (_) => _buscarNotificacoesInternas(),
        )
        .subscribe();
  }

  Future<void> _buscarNotificacoesInternas() async {
    final usuarioId = Supabase.instance.client.auth.currentUser?.id;
    if (!mounted || usuarioId == null) return;
    final versao = ++_versaoConsultaNotificacoes;
    setState(() => _carregandoNotificacoes = true);
    try {
      final agora = DateTime.now().toUtc().toIso8601String();
      final registros = await Supabase.instance.client
          .from('tab_notificacoes_internas')
          .select('id,titulo,mensagem,tipo,categoria,destino,lida,criada_em,'
              'publicada_em,imagem_url,texto_botao,prioridade,dados_extras')
          .eq('usuario_id', usuarioId)
          .eq('tipo_registro', 'notificacao')
          .eq('status', 'publicada')
          .eq('ativo', true)
          .isFilter('arquivada_em', null)
          .not('publicada_em', 'is', null)
          .lte('publicada_em', agora)
          .or('expira_em.is.null,expira_em.gt.$agora')
          .order('criada_em', ascending: false)
          .limit(100);
      if (!mounted ||
          versao != _versaoConsultaNotificacoes ||
          Supabase.instance.client.auth.currentUser?.id != usuarioId) return;
      final lista = List<Map<String, dynamic>>.from(registros);
      setState(() {
        _notificacoesInternas = lista;
        _notificacoesNaoLidas = lista.where((n) => n['lida'] != true).length;
        _erroNotificacoes = null;
        _carregandoNotificacoes = false;
      });
      _mudancasNotificacoes.value++;
    } catch (e) {
      debugPrint('Erro ao carregar notificações internas: $e');
      if (!mounted || versao != _versaoConsultaNotificacoes) return;
      setState(() {
        _erroNotificacoes = 'Não foi possível carregar as notificações.';
        _carregandoNotificacoes = false;
      });
      _mudancasNotificacoes.value++;
    }
  }

  Future<bool> _executarAcaoNotificacao(String id, String funcao) async {
    try {
      final resultado = await Supabase.instance.client.rpc(
        funcao,
        params: {'p_notificacao_id': id},
      );
      if (resultado != true) {
        throw Exception('Notificação não disponível ou sem permissão.');
      }
      await _buscarNotificacoesInternas();
      return true;
    } catch (e) {
      debugPrint('Erro em $funcao: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
              content: Text('Não foi possível atualizar a notificação.')),
        );
      }
      return false;
    }
  }

  String _dataNotificacao(dynamic valor) {
    final data = DateTime.tryParse(valor?.toString() ?? '')?.toLocal();
    if (data == null) return '';
    String dois(int n) => n.toString().padLeft(2, '0');
    return '${dois(data.day)}/${dois(data.month)}/${data.year} '
        '${dois(data.hour)}:${dois(data.minute)}';
  }

  Future<void> _abrirDestinoNotificacao(
      Map<String, dynamic> notificacao) async {
    final destino = (notificacao['destino'] ?? '').toString().trim();
    if (destino.isEmpty) return;
    final rota = destino.toLowerCase().replaceAll('/', '').replaceAll('_', '');
    Widget? pagina;
    switch (rota) {
      case 'perfil':
      case 'editarperfil':
        pagina = const ClienteHomePage(abaInicial: 0);
        break;
      case 'servicos':
      case 'serviços':
        pagina = const ClienteHomePage(abaInicial: 1);
        break;
      case 'listadecompras':
      case 'compras':
        pagina = const ClienteHomePage(abaInicial: 2);
        break;
      case 'planos':
      case 'meusplanos':
        pagina = PlanosUsuarioPage(tipoUsuarioLogado: _tipoUsuarioLogado);
        break;
      case 'mensagens':
      case 'conversas':
        pagina = const ListaConversasPage();
        break;
      case 'jisa':
      case 'ia':
        pagina = const IaPage();
        break;
      case 'orcamentos':
      case 'orçamentos':
        pagina = const ListaOrcamentosPage();
        break;
      case 'selo':
        pagina = const SeloVerificacaoPage();
        break;
      case 'faq':
        pagina = const FaqPage();
        break;
      case 'suporte':
        pagina = const SuporteEmailPage();
        break;
      case 'feed':
        return;
    }
    if (!mounted) return;
    if (pagina != null) {
      await Navigator.push(context, MaterialPageRoute(builder: (_) => pagina!));
      if (mounted) _buscarNotificacoesInternas();
    } else {
      // Destinos desconhecidos não são abertos como URLs arbitrárias.
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text('Destino ainda não configurado no aplicativo.')),
      );
    }
  }

  void _abrirCentralNotificacoes() {
    if (!mounted) return;
    _buscarNotificacoesInternas();
    showModalBottomSheet<void>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (contextoModal) {
        return ValueListenableBuilder<int>(
          valueListenable: _mudancasNotificacoes,
          builder: (contextoModal, _, __) => StatefulBuilder(
            builder: (contextoModal, atualizarModal) {
              // AnimatedBuilder observa o estado do Feed por meio de um
              // ValueNotifier local atualizado na consulta (ver abaixo).
              return SafeArea(
                child: Container(
                  height: MediaQuery.sizeOf(contextoModal).height * 0.72,
                  margin: const EdgeInsets.fromLTRB(12, 0, 12, 12),
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF1A2C42),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                        color: const Color(0xFFFF8C00).withValues(alpha: 0.35)),
                  ),
                  child: Column(
                    children: [
                      Container(
                          width: 42,
                          height: 4,
                          decoration: BoxDecoration(
                              color: Colors.white24,
                              borderRadius: BorderRadius.circular(2))),
                      const SizedBox(height: 12),
                      Row(children: [
                        const Icon(Icons.notifications_none_rounded,
                            color: Color(0xFFFF8C00), size: 26),
                        const SizedBox(width: 10),
                        const Expanded(
                            child: Text('Notificações',
                                style: TextStyle(
                                    color: Colors.white,
                                    fontSize: 18,
                                    fontWeight: FontWeight.bold))),
                        IconButton(
                          tooltip: 'Atualizar',
                          icon: const Icon(Icons.refresh, color: Colors.white),
                          onPressed: () async {
                            await _buscarNotificacoesInternas();
                            if (contextoModal.mounted) atualizarModal(() {});
                          },
                        ),
                        IconButton(
                          tooltip: 'Fechar',
                          icon: const Icon(Icons.close, color: Colors.white70),
                          onPressed: () => Navigator.pop(contextoModal),
                        ),
                      ]),
                      const Divider(color: Colors.white24),
                      Expanded(
                        child: _carregandoNotificacoes &&
                                _notificacoesInternas.isEmpty
                            ? const Center(
                                child: CircularProgressIndicator(
                                    color: Color(0xFFFF8C00)))
                            : _erroNotificacoes != null &&
                                    _notificacoesInternas.isEmpty
                                ? Center(
                                    child: Text(_erroNotificacoes!,
                                        style: const TextStyle(
                                            color: Colors.white70)))
                                : _notificacoesInternas.isEmpty
                                    ? const Center(
                                        child: Text(
                                            'Nenhuma notificação no momento.',
                                            style: TextStyle(
                                                color: Colors.white70)))
                                    : ListView.separated(
                                        itemCount: _notificacoesInternas.length,
                                        separatorBuilder: (_, __) =>
                                            const SizedBox(height: 8),
                                        itemBuilder: (contextoItem, indice) {
                                          final n =
                                              _notificacoesInternas[indice];
                                          final id = n['id'].toString();
                                          final naoLida = n['lida'] != true;
                                          final imagem = (n['imagem_url'] ?? '')
                                              .toString();
                                          final destino = (n['destino'] ?? '')
                                              .toString()
                                              .trim();
                                          return Container(
                                            padding: const EdgeInsets.all(12),
                                            decoration: BoxDecoration(
                                              color: naoLida
                                                  ? const Color(0xFF304B6B)
                                                  : const Color(0xFF253C59),
                                              borderRadius:
                                                  BorderRadius.circular(12),
                                              border: Border.all(
                                                  color: naoLida
                                                      ? const Color(0xFFFF8C00)
                                                          .withValues(
                                                              alpha: 0.45)
                                                      : Colors.white12),
                                            ),
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              children: [
                                                Row(children: [
                                                  if (naoLida) ...[
                                                    const Icon(Icons.circle,
                                                        size: 9,
                                                        color:
                                                            Color(0xFFFF8C00)),
                                                    const SizedBox(width: 8),
                                                  ],
                                                  Expanded(
                                                      child: Text(
                                                    (n['titulo'] ?? '')
                                                        .toString(),
                                                    style: const TextStyle(
                                                        color: Colors.white,
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        fontSize: 15),
                                                  )),
                                                  Text(
                                                      _dataNotificacao(
                                                          n['criada_em']),
                                                      style: const TextStyle(
                                                          color: Colors.white54,
                                                          fontSize: 10)),
                                                ]),
                                                const SizedBox(height: 8),
                                                Text(
                                                    (n['mensagem'] ?? '')
                                                        .toString(),
                                                    style: const TextStyle(
                                                        color: Colors.white70,
                                                        fontSize: 13)),
                                                if (imagem.startsWith(
                                                        'https://') ||
                                                    imagem.startsWith(
                                                        'http://')) ...[
                                                  const SizedBox(height: 10),
                                                  ClipRRect(
                                                    borderRadius:
                                                        BorderRadius.circular(
                                                            8),
                                                    child: Image.network(imagem,
                                                        height: 130,
                                                        width: double.infinity,
                                                        fit: BoxFit.cover,
                                                        errorBuilder:
                                                            (_, __, ___) =>
                                                                const SizedBox
                                                                    .shrink()),
                                                  ),
                                                ],
                                                const SizedBox(height: 8),
                                                Wrap(
                                                    spacing: 8,
                                                    runSpacing: 4,
                                                    children: [
                                                      if (naoLida)
                                                        TextButton.icon(
                                                          style: TextButton
                                                              .styleFrom(
                                                            foregroundColor:
                                                                const Color(
                                                                    0xFFFF8C00),
                                                          ),
                                                          icon: const Icon(
                                                              Icons.done,
                                                              size: 16),
                                                          label: const Text(
                                                              'Marcar como lida'),
                                                          onPressed: () async {
                                                            await _executarAcaoNotificacao(
                                                                id,
                                                                'internas_marcar_como_lida');
                                                            if (contextoModal
                                                                .mounted)
                                                              atualizarModal(
                                                                  () {});
                                                          },
                                                        ),
                                                      if (destino.isNotEmpty)
                                                        TextButton.icon(
                                                          style: TextButton
                                                              .styleFrom(
                                                            foregroundColor:
                                                                const Color(
                                                                    0xFFFF8C00),
                                                          ),
                                                          icon: const Icon(
                                                              Icons.open_in_new,
                                                              size: 16),
                                                          label: Text(
                                                              (n['texto_botao'] ??
                                                                      'Abrir')
                                                                  .toString()),
                                                          onPressed: () async {
                                                            if (naoLida) {
                                                              await _executarAcaoNotificacao(
                                                                  id,
                                                                  'internas_marcar_como_lida');
                                                            }
                                                            if (!contextoModal
                                                                .mounted)
                                                              return;
                                                            Navigator.pop(
                                                                contextoModal);
                                                            await _abrirDestinoNotificacao(
                                                                n);
                                                          },
                                                        ),
                                                      TextButton.icon(
                                                        style: TextButton
                                                            .styleFrom(
                                                          foregroundColor:
                                                              const Color(
                                                                  0xFFFF8C00),
                                                        ),
                                                        icon: const Icon(
                                                            Icons
                                                                .archive_outlined,
                                                            size: 16),
                                                        label: const Text(
                                                            'Arquivar'),
                                                        onPressed: () async {
                                                          await _executarAcaoNotificacao(
                                                              id,
                                                              'internas_arquivar_notificacao');
                                                          if (contextoModal
                                                              .mounted)
                                                            atualizarModal(
                                                                () {});
                                                        },
                                                      ),
                                                    ]),
                                              ],
                                            ),
                                          );
                                        },
                                      ),
                      ),
                    ],
                  ),
                ),
              );
            },
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    bool isProfissional = _tipoUsuarioLogado == 'profissional' ||
        _tipoUsuarioLogado == 'arquiteto' ||
        _tipoUsuarioLogado == 'engenheiro';

    return Scaffold(
      backgroundColor: const Color(0xFF1A2C42),
      appBar: AppBar(
        backgroundColor: const Color(0xFF1A2C42),
        elevation: 0,
        titleSpacing: 0,
        leading: Builder(
          builder: (context) => IconButton(
            icon: const Icon(Icons.menu, color: Colors.white, size: 24),
            onPressed: () => Scaffold.of(context).openDrawer(),
          ),
        ),
        title: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            GestureDetector(
              onTap: () => Scaffold.of(context).openDrawer(),
              child: CircleAvatar(
                radius: 16,
                backgroundColor: const Color(0xFFFF8C00),
                backgroundImage:
                    (_userFotoUrl != null && _userFotoUrl!.trim().isNotEmpty)
                        ? NetworkImage(_userFotoUrl!.trim())
                        : null,
                child: (_userFotoUrl == null || _userFotoUrl!.trim().isEmpty)
                    ? const Icon(Icons.person, size: 18, color: Colors.white)
                    : null,
              ),
            ),
            const SizedBox(width: 6),
            const Text(
              "Ache Obra",
              style: TextStyle(
                color: Color(0xFFFF8C00),
                fontWeight: FontWeight.bold,
                fontSize: 17,
              ),
            ),
            IconButton(
              constraints: const BoxConstraints(),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              icon: const Icon(Icons.refresh, color: Colors.white70, size: 26),
              tooltip: 'Atualizar Feed',
              onPressed: () {
                _carregarTipoUsuarioLogado();
              },
            ),
            IconButton(
              constraints: const BoxConstraints(),
              padding: const EdgeInsets.symmetric(horizontal: 4),
              icon: Stack(
                clipBehavior: Clip.none,
                children: [
                  const Icon(Icons.notifications_none_rounded,
                      color: Colors.white70, size: 27),
                  if (_notificacoesNaoLidas > 0)
                    Positioned(
                      right: -9,
                      top: -7,
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 4, vertical: 2),
                        constraints: const BoxConstraints(minWidth: 17),
                        decoration: BoxDecoration(
                          color: Colors.redAccent,
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Text(
                          _notificacoesNaoLidas > 99
                              ? '99+'
                              : '$_notificacoesNaoLidas',
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 9,
                              fontWeight: FontWeight.bold),
                        ),
                      ),
                    ),
                ],
              ),
              tooltip: 'Notificações',
              onPressed: _abrirCentralNotificacoes,
            ),
          ],
        ),
        actions: [
          Center(
            child: Padding(
              padding: const EdgeInsets.only(right: 6),
              child: SizedBox(
                height: 36,
                child: ElevatedButton.icon(
                  onPressed: () async {
                    showDialog(
                      context: context,
                      barrierDismissible: false,
                      builder: (context) => const Center(
                        child:
                            CircularProgressIndicator(color: Color(0xFFFF8C00)),
                      ),
                    );

                    String tipoDescoberto = 'Cliente';
                    final user = Supabase.instance.client.auth.currentUser;

                    if (user != null) {
                      try {
                        var data = await Supabase.instance.client
                            .from('tab_usuarios')
                            .select()
                            .eq('id', user.id)
                            .maybeSingle();

                        if (data == null) {
                          try {
                            data = await Supabase.instance.client
                                .from('tab_usuarios_profissionais')
                                .select()
                                .eq('id', user.id)
                                .maybeSingle();
                          } catch (_) {}
                        }

                        if (data != null) {
                          String t = (data['tipo'] ??
                                  data['tipo_usuario'] ??
                                  data['perfil'] ??
                                  '')
                              .toString();
                          if (t.trim().isNotEmpty &&
                              t.trim().toLowerCase() != 'null') {
                            tipoDescoberto = t.trim();
                          }
                        }
                      } catch (e) {
                        debugPrint(
                            'Erro ao buscar tipo antes de abrir planos: $e');
                      }
                    }

                    if (context.mounted) Navigator.pop(context);

                    if (context.mounted) {
                      await Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (context) => PlanosUsuarioPage(
                            tipoUsuarioLogado: tipoDescoberto,
                          ),
                        ),
                      );
                      _carregarTipoUsuarioLogado();
                    }
                  },
                  icon: const Icon(Icons.star, size: 16, color: Colors.white),
                  label: const Text(
                    "Seja Pró",
                    style: TextStyle(fontSize: 13, fontWeight: FontWeight.bold),
                  ),
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF8C00),
                    foregroundColor: Colors.white,
                    elevation: 2,
                    padding: const EdgeInsets.symmetric(horizontal: 12),
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(20),
                    ),
                  ),
                ),
              ),
            ),
          ),
          PopupMenuButton<String>(
            icon: const Icon(Icons.filter_list, color: Colors.white, size: 24),
            tooltip: 'Filtrar',
            color: const Color(0xFF253c59),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(12),
              side: const BorderSide(color: Colors.white24, width: 0.5),
            ),
            onSelected: (val) {
              if (val == 'Todos') {
                setState(() {
                  _filtroTipoPrincipal = 'Todos';
                  _profissaoSelecionada = null;
                  _servicoSelecionado = null;
                  _filtroEstadoSelecionado = null;
                  _filtroCidadeSelecionada = null;
                  _filtroNomePesquisado = null;
                });
                _carregarDemandas();
              } else if (val == 'Nome') {
                _mostrarModalBuscaPorNome();
              } else if (val == 'Profissionais') {
                setState(() {
                  _filtroTipoPrincipal = 'Profissionais';
                });
                _mostrarModalSelecaoProfissao();
              } else if (val == 'Arquitetos') {
                setState(() {
                  _filtroTipoPrincipal = 'Arquitetos';
                  _profissaoSelecionada = null;
                });
                _carregarDemandas();
              } else if (val == 'Engenheiros') {
                setState(() {
                  _filtroTipoPrincipal = 'Engenheiros';
                  _profissaoSelecionada = null;
                });
                _carregarDemandas();
              } else if (val == 'Clientes') {
                setState(() {
                  _filtroTipoPrincipal = 'Clientes';
                  _profissaoSelecionada = null;
                });
                _carregarDemandas();
              } else if (val == 'Serviços') {
                _mostrarModalSelecaoServico();
              } else if (val == 'Localização') {
                _mostrarModalFiltroLocalizacao();
              }
            },
            itemBuilder: (BuildContext context) {
              return _filtrosBase.map((String value) {
                return PopupMenuItem<String>(
                  value: value,
                  child: Text(
                    value,
                    style: const TextStyle(
                      color: Colors.white,
                      fontSize: 14,
                      fontWeight: FontWeight.w500,
                    ),
                  ),
                );
              }).toList();
            },
          ),
          const SizedBox(width: 4),
        ],
      ),
      drawer: _buildMenuPrincipalIcones(
        isProfissional,
      ),
      onDrawerChanged: (aberto) {
        if (!aberto && _submenuMenuAberto != null && mounted) {
          setState(() {
            _submenuMenuAberto = null;
          });
        }
      },
      body: RefreshIndicator(
        color: const Color(0xFFFF8C00),
        backgroundColor: const Color(0xFF253c59),
        onRefresh: () async {
          await _carregarTipoUsuarioLogado();
        },
        child: FutureBuilder<List<Map<String, dynamic>>>(
          future: _futureDemandas,
          builder: (context, snapshot) {
            if (snapshot.connectionState == ConnectionState.waiting) {
              return const Center(
                child: Padding(
                    padding: EdgeInsets.all(40.0),
                    child: CircularProgressIndicator(color: Color(0xFFFF8C00))),
              );
            }
            if (snapshot.hasError) {
              return Padding(
                padding: const EdgeInsets.all(20.0),
                child: Center(
                  child: Text("Erro ao carregar o feed: ${snapshot.error}",
                      style: const TextStyle(color: Colors.redAccent),
                      textAlign: TextAlign.center),
                ),
              );
            }
            final demandas = snapshot.data ?? [];
            final destaquesReais =
                demandas.where((d) => d['is_perfil_card'] != true).toList();

            return ListView(
              physics: const AlwaysScrollableScrollPhysics(),
              children: [
                _buildHistoricoFiltrosWidget(),
                SizedBox(
                  height: 140,
                  child: destaquesReais.isEmpty
                      ? ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: 3,
                          itemBuilder: (context, index) =>
                              _buildDestaqueCardPlaceholder(
                                  "Exemplo ${index + 1}"),
                        )
                      : ListView.builder(
                          scrollDirection: Axis.horizontal,
                          itemCount: destaquesReais.length > 5
                              ? 5
                              : destaquesReais.length,
                          itemBuilder: (context, index) {
                            final demanda = destaquesReais[index];
                            return _buildDestaqueCardReal(context, demanda);
                          },
                        ),
                ),
                const Divider(color: Colors.white24),
                demandas.isEmpty
                    ? const Padding(
                        padding: EdgeInsets.all(40.0),
                        child: Center(
                            child: Text("Nenhuma demanda encontrada.",
                                style: TextStyle(color: Colors.white54))),
                      )
                    : ListView.builder(
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        itemCount: demandas.length,
                        itemBuilder: (context, index) {
                          final demanda = demandas[index];
                          if (demanda['is_perfil_card'] == true) {
                            return _buildPerfilUsuarioCard(
                                context, demanda['dados_perfil']);
                          }
                          return _buildServicoCard(context, demanda);
                        },
                      ),
                const SizedBox(height: 80),
              ],
            );
          },
        ),
      ),
      floatingActionButton: FloatingActionButton.extended(
        onPressed: () {
          Navigator.push(
            context,
            MaterialPageRoute(
              builder: (context) => const ClienteHomePage(abaInicial: 1),
            ),
          );
        },
        backgroundColor: const Color(0xFFFF8C00),
        foregroundColor: Colors.white,
        elevation: 4,
        icon: const Icon(Icons.add_circle_outline, color: Colors.white),
        label: const Text(
          "Publicar Serviço",
          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
        ),
      ),
      floatingActionButtonLocation: FloatingActionButtonLocation.startFloat,
      bottomNavigationBar: Container(
        height: 60,
        decoration: const BoxDecoration(
          color: Color(0xFF253c59),
          border: Border(top: BorderSide(color: Colors.white24, width: 0.5)),
        ),
        child: Row(
          children: [
            Expanded(
              child: _buildBotaoRodape(
                onPressed: () async {
                  await Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const ListaConversasPage(),
                    ),
                  );

                  // Quando o usuário volta de Minhas Conversas, recria o stream
                  // para que mensagens já lidas desapareçam do badge na hora.
                  if (mounted) {
                    _atualizarContadorMensagens();
                  }
                },
                icon: StreamBuilder<List<Map<String, dynamic>>>(
                  key: ValueKey(_mensagensStreamRefresh),
                  stream: Supabase.instance.client
                      .from('tab_mensagens')
                      .stream(primaryKey: ['id'])
                      .eq('lida', false)
                      .order('created_at', ascending: true),
                  builder: (context, snapshot) {
                    int naoLidas = 0;
                    if (snapshot.hasData && snapshot.data != null) {
                      final meuId =
                          Supabase.instance.client.auth.currentUser?.id;
                      naoLidas = snapshot.data!
                          .where((msg) => msg['remetente_id'] != meuId)
                          .length;
                    }

                    return Badge(
                      isLabelVisible: naoLidas > 0,
                      label: Text('$naoLidas'),
                      child: const Icon(
                        Icons.chat,
                        color: Color(0xFFFF8C00),
                        size: 18,
                      ),
                    );
                  },
                ),
                label: 'Mensagens',
                destaque: true,
              ),
            ),
            Expanded(
              child: _buildBotaoRodape(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const DetalhesCampanhaPage(),
                    ),
                  );
                },
                icon: const Icon(
                  Icons.emoji_events_outlined,
                  color: Colors.white70,
                  size: 18,
                ),
                label: 'Prêmios',
              ),
            ),
            Expanded(
              child: _buildBotaoRodape(
                onPressed: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const IaPage(),
                    ),
                  );
                },
                icon: const Icon(
                  Icons.auto_awesome,
                  color: Color(0xFFFF8C00),
                  size: 19,
                ),
                label: 'Jisa IA',
                destaque: true,
              ),
            ),
            Expanded(
              child: _buildBotaoRodape(
                onPressed: () {
                  Share.share(
                    '🚀 Conheça o Ache Obra! Baixe o aplicativo na Google Play: https://play.google.com/store/apps/details?id=br.com.acheobra.app',
                  );
                },
                icon: const Icon(
                  Icons.share_outlined,
                  color: Colors.white70,
                  size: 18,
                ),
                label: 'Compartilhar',
              ),
            ),
            Expanded(
              child: _buildBotaoRodape(
                onPressed: () {
                  _mostrarMenuAtalhos(context);
                },
                icon: const Icon(
                  Icons.bolt,
                  color: Color(0xFFFF8C00),
                  size: 18,
                ),
                label: 'Atalho',
                destaque: true,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildBotaoRodape({
    required VoidCallback onPressed,
    required Widget icon,
    required String label,
    bool destaque = false,
  }) {
    return TextButton(
      onPressed: onPressed,
      style: TextButton.styleFrom(
        padding: const EdgeInsets.symmetric(horizontal: 1, vertical: 3),
        minimumSize: Size.zero,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        shape: const RoundedRectangleBorder(),
      ),
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        mainAxisSize: MainAxisSize.min,
        children: [
          SizedBox(
            height: 21,
            child: Center(child: icon),
          ),
          const SizedBox(height: 1),
          FittedBox(
            fit: BoxFit.scaleDown,
            child: Text(
              label,
              maxLines: 1,
              style: TextStyle(
                color: destaque ? Colors.white : Colors.white70,
                fontSize: 9.2,
                fontWeight: destaque ? FontWeight.w600 : FontWeight.normal,
              ),
            ),
          ),
        ],
      ),
    );
  }

  void _mostrarMenuAtalhos(BuildContext context) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A2C42),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                "Atalhos Rápidos",
                style: TextStyle(
                  color: Color(0xFFFF8C00),
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 10),
              const Divider(color: Colors.white24),
              ListTile(
                leading: const Icon(
                  Icons.auto_awesome,
                  color: Color(0xFFFF8C00),
                ),
                title: const Text(
                  "Jisa IA",
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                subtitle: const Text(
                  "Sua assistente de construção",
                  style: TextStyle(color: Colors.white54, fontSize: 12),
                ),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) => const IaPage(),
                    ),
                  );
                },
              ),
              const Divider(color: Colors.white24),
              ListTile(
                leading:
                    const Icon(Icons.request_quote, color: Color(0xFFFF8C00)),
                title: const Text("Orçamento",
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold)),
                subtitle: const Text("Acompanhe seus orçamentos",
                    style: TextStyle(color: Colors.white54, fontSize: 12)),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                        builder: (context) => const ListaOrcamentosPage()),
                  );
                },
              ),
              const Divider(color: Colors.white24),
              ListTile(
                leading: const Icon(Icons.shopping_cart_checkout,
                    color: Color(0xFFFF8C00)),
                title: const Text("Lista de Compras",
                    style: TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold)),
                subtitle: const Text("Veja sua lista de materiais",
                    style: TextStyle(color: Colors.white54, fontSize: 12)),
                onTap: () {
                  Navigator.pop(context);
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (context) =>
                          const ClienteHomePage(abaInicial: 2),
                    ),
                  );
                },
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildHistoricoFiltrosWidget() {
    bool temFiltroAtivo = _filtroTipoPrincipal != 'Todos' ||
        _profissaoSelecionada != null ||
        _servicoSelecionado != null ||
        _filtroEstadoSelecionado != null ||
        _filtroCidadeSelecionada != null ||
        _filtroNomePesquisado != null;

    if (!temFiltroAtivo) return const SizedBox.shrink();

    List<Widget> chips = [];

    if (_filtroTipoPrincipal != 'Todos') {
      chips.add(_buildChipFiltro(
        label: 'Tipo: $_filtroTipoPrincipal',
        onDeleted: () {
          setState(() {
            _filtroTipoPrincipal = 'Todos';
            _profissaoSelecionada = null;
          });
          _carregarDemandas();
        },
      ));
    }

    if (_filtroNomePesquisado != null) {
      chips.add(_buildChipFiltro(
        label: 'Nome: $_filtroNomePesquisado',
        onDeleted: () {
          setState(() {
            _filtroNomePesquisado = null;
          });
          _carregarDemandas();
        },
      ));
    }

    if (_profissaoSelecionada != null) {
      chips.add(_buildChipFiltro(
        label: 'Profissão: $_profissaoSelecionada',
        onDeleted: () {
          setState(() {
            _profissaoSelecionada = null;
          });
          _carregarDemandas();
        },
      ));
    }

    if (_servicoSelecionado != null) {
      chips.add(_buildChipFiltro(
        label: 'Serviço: $_servicoSelecionado',
        onDeleted: () {
          setState(() {
            _servicoSelecionado = null;
          });
          _carregarDemandas();
        },
      ));
    }

    if (_filtroEstadoSelecionado != null || _filtroCidadeSelecionada != null) {
      String localLabel =
          'Local: ${_filtroCidadeSelecionada ?? ''} ${_filtroCidadeSelecionada != null && _filtroEstadoSelecionado != null ? '/' : ''} ${_filtroEstadoSelecionado ?? ''}'
              .trim();
      chips.add(_buildChipFiltro(
        label: localLabel,
        onDeleted: () {
          setState(() {
            _filtroEstadoSelecionado = null;
            _filtroCidadeSelecionada = null;
          });
          _carregarDemandas();
        },
      ));
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      color: const Color(0xFF253c59),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              const Text("Filtros Ativos:",
                  style: TextStyle(
                      color: Color(0xFFFF8C00),
                      fontWeight: FontWeight.bold,
                      fontSize: 13)),
              TextButton(
                onPressed: () {
                  setState(() {
                    _filtroTipoPrincipal = 'Todos';
                    _profissaoSelecionada = null;
                    _servicoSelecionado = null;
                    _filtroEstadoSelecionado = null;
                    _filtroCidadeSelecionada = null;
                    _filtroNomePesquisado = null;
                  });
                  _carregarDemandas();
                },
                child: const Text("Limpar Tudo",
                    style: TextStyle(color: Colors.white70, fontSize: 12)),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Wrap(
            spacing: 8,
            runSpacing: 4,
            children: chips,
          ),
        ],
      ),
    );
  }

  Widget _buildChipFiltro(
      {required String label, required VoidCallback onDeleted}) {
    return Chip(
      backgroundColor: const Color(0xFF1A2C42),
      deleteIconColor: const Color(0xFFFF8C00),
      label: Text(label,
          style: const TextStyle(color: Colors.white, fontSize: 12)),
      onDeleted: onDeleted,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(20),
        side: const BorderSide(color: Color(0xFFFF8C00), width: 1),
      ),
    );
  }

  void _mostrarModalBuscaPorNome() {
    final TextEditingController controladorNome =
        TextEditingController(text: _filtroNomePesquisado);

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A2C42),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(context).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Buscar por Nome",
                  style: TextStyle(
                      color: Color(0xFFFF8C00),
                      fontSize: 18,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              const Divider(color: Colors.white24),
              const SizedBox(height: 10),
              TextField(
                controller: controladorNome,
                style: const TextStyle(color: Colors.white),
                decoration: const InputDecoration(
                  filled: true,
                  fillColor: Colors.white12,
                  hintText: "Digite o nome do profissional ou cliente",
                  hintStyle: TextStyle(color: Colors.white54),
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: 20),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton(
                  onPressed: () {
                    setState(() {
                      _filtroNomePesquisado =
                          controladorNome.text.trim().isNotEmpty
                              ? controladorNome.text.trim()
                              : null;
                    });
                    Navigator.pop(context);
                    _carregarDemandas();
                  },
                  style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF8C00),
                    padding: const EdgeInsets.symmetric(vertical: 14),
                  ),
                  child: const Text("PESQUISAR",
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _mostrarModalSelecaoProfissao() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A2C42),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Selecione a Profissão",
                  style: TextStyle(
                      color: Color(0xFFFF8C00),
                      fontSize: 18,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              const Divider(color: Colors.white24),
              Expanded(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _listaServicosDisponiveis.length,
                  itemBuilder: (context, index) {
                    final prof = _listaServicosDisponiveis[index];
                    return ListTile(
                      title: Text(prof,
                          style: const TextStyle(color: Colors.white)),
                      trailing: const Icon(Icons.arrow_forward_ios,
                          color: Colors.white54, size: 16),
                      onTap: () {
                        setState(() {
                          _profissaoSelecionada = prof;
                        });
                        Navigator.pop(context);
                        _carregarDemandas();
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _mostrarModalSelecaoServico() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A2C42),
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return Container(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text("Selecione 1 Serviço",
                  style: TextStyle(
                      color: Color(0xFFFF8C00),
                      fontSize: 18,
                      fontWeight: FontWeight.bold)),
              const SizedBox(height: 10),
              const Divider(color: Colors.white24),
              Expanded(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: _listaServicosDisponiveis.length,
                  itemBuilder: (context, index) {
                    final servico = _listaServicosDisponiveis[index];
                    return ListTile(
                      title: Text(servico,
                          style: const TextStyle(color: Colors.white)),
                      trailing: const Icon(Icons.arrow_forward_ios,
                          color: Colors.white54, size: 16),
                      onTap: () {
                        setState(() {
                          _servicoSelecionado = servico;
                        });
                        Navigator.pop(context);
                        _carregarDemandas();
                      },
                    );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _mostrarModalFiltroLocalizacao() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A2C42),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return StatefulBuilder(
          builder: (BuildContext context, StateSetter setModalState) {
            return Padding(
              padding: EdgeInsets.only(
                left: 20,
                right: 20,
                top: 20,
                bottom: MediaQuery.of(context).viewInsets.bottom + 20,
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text("Filtrar por Localização",
                      style: TextStyle(
                          color: Color(0xFFFF8C00),
                          fontSize: 18,
                          fontWeight: FontWeight.bold)),
                  const SizedBox(height: 10),
                  const Divider(color: Colors.white24),
                  const SizedBox(height: 10),
                  const Text("Estado (UF):",
                      style: TextStyle(color: Colors.white70)),
                  const SizedBox(height: 5),
                  DropdownButtonFormField<String>(
                    value: _filtroEstadoSelecionado,
                    isExpanded: true,
                    dropdownColor: const Color(0xFF253c59),
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold),
                    decoration: const InputDecoration(
                      filled: true,
                      fillColor: Colors.white12,
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(vertical: 12, horizontal: 10),
                    ),
                    hint: const Text("Selecione o Estado",
                        style: TextStyle(color: Colors.white54)),
                    items: _listaEstados.map((String estado) {
                      return DropdownMenuItem<String>(
                          value: estado, child: Text(estado));
                    }).toList(),
                    onChanged: (val) async {
                      setModalState(() {
                        _filtroEstadoSelecionado = val;
                        _filtroCidadeSelecionada = null;
                        _listaCidadesFiltro = [];
                        _carregandoCidadesFiltro = true;
                      });
                      if (val != null) {
                        try {
                          final data = await Supabase.instance.client
                              .from('tab_localidades')
                              .select('municipio')
                              .eq('estado', val)
                              .order('municipio', ascending: true);
                          setModalState(() {
                            _listaCidadesFiltro = (data as List)
                                .map((e) => e['municipio'].toString())
                                .toList();
                            _carregandoCidadesFiltro = false;
                          });
                        } catch (e) {
                          setModalState(() => _carregandoCidadesFiltro = false);
                        }
                      }
                    },
                  ),
                  const SizedBox(height: 15),
                  const Text("Cidade (Opcional):",
                      style: TextStyle(color: Colors.white70)),
                  const SizedBox(height: 5),
                  DropdownButtonFormField<String>(
                    value: _filtroCidadeSelecionada,
                    isExpanded: true,
                    dropdownColor: const Color(0xFF253c59),
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold),
                    decoration: const InputDecoration(
                      filled: true,
                      fillColor: Colors.white12,
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(vertical: 12, horizontal: 10),
                    ),
                    hint: _carregandoCidadesFiltro
                        ? const Text("Carregando cidades...",
                            style: TextStyle(color: Colors.white54))
                        : const Text("Selecione a cidade",
                            style: TextStyle(color: Colors.white54)),
                    items: _listaCidadesFiltro.map((String cidade) {
                      return DropdownMenuItem<String>(
                          value: cidade, child: Text(cidade));
                    }).toList(),
                    onChanged: (_carregandoCidadesFiltro ||
                            _listaCidadesFiltro.isEmpty)
                        ? null
                        : (val) {
                            setModalState(() {
                              _filtroCidadeSelecionada = val;
                            });
                          },
                  ),
                  const SizedBox(height: 25),
                  SizedBox(
                    width: double.infinity,
                    child: ElevatedButton(
                      onPressed: () {
                        Navigator.pop(context);
                        _carregarDemandas();
                      },
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF8C00),
                        padding: const EdgeInsets.symmetric(vertical: 14),
                      ),
                      child: const Text("APLICAR FILTRO",
                          style: TextStyle(
                              color: Colors.white,
                              fontWeight: FontWeight.bold)),
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  }

  String _normalizarFiltro(dynamic valor) {
    return (valor ?? '')
        .toString()
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[áàãâä]'), 'a')
        .replaceAll(RegExp(r'[éèêë]'), 'e')
        .replaceAll(RegExp(r'[íìîï]'), 'i')
        .replaceAll(RegExp(r'[óòõôö]'), 'o')
        .replaceAll(RegExp(r'[úùûü]'), 'u')
        .replaceAll('ç', 'c')
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  bool _textoFiltroIgual(dynamic valor, String? filtro) {
    if (filtro == null || filtro.trim().isEmpty) return true;
    return _normalizarFiltro(valor) == _normalizarFiltro(filtro);
  }

  bool _textoFiltroContem(dynamic valor, String? filtro) {
    if (filtro == null || filtro.trim().isEmpty) return true;
    return _normalizarFiltro(valor).contains(_normalizarFiltro(filtro));
  }

  List<String> _valoresComoLista(dynamic valor) {
    if (valor == null) return <String>[];

    if (valor is List) {
      return valor
          .where((e) => e != null && e.toString().trim().isNotEmpty)
          .map((e) => e.toString().trim())
          .toList();
    }

    final texto = valor.toString().trim();
    if (texto.isEmpty) return <String>[];

    return texto
        .split(RegExp(r'[,;|]'))
        .map((e) => e.trim())
        .where((e) => e.isNotEmpty)
        .toList();
  }

  bool _listaContemFiltro(dynamic valor, String? filtro) {
    if (filtro == null || filtro.trim().isEmpty) return true;
    final alvo = _normalizarFiltro(filtro);

    return _valoresComoLista(valor).any((item) {
      final normalizado = _normalizarFiltro(item);
      return normalizado == alvo ||
          normalizado.contains(alvo) ||
          alvo.contains(normalizado);
    });
  }

  bool _itemPassaNosFiltros(Map<String, dynamic> item) {
    final bool perfilCard = item['is_perfil_card'] == true;
    final dadosUsuario = perfilCard
        ? _extrairDadosUsuario(item['dados_perfil'])
        : _extrairDadosUsuario(item['tab_usuarios']);

    final papel = _obterPapelAutor(dadosUsuario);

    if (_filtroTipoPrincipal == 'Profissionais' && papel != 'PROFISSIONAL') {
      return false;
    }

    if (_filtroTipoPrincipal == 'Arquitetos' && papel != 'ARQUITETO') {
      return false;
    }

    if (_filtroTipoPrincipal == 'Engenheiros' && papel != 'ENGENHEIRO') {
      return false;
    }

    if (_filtroTipoPrincipal == 'Clientes' && papel != 'CLIENTE') {
      return false;
    }

    if (_filtroTipoPrincipal == 'Profissionais' &&
        _profissaoSelecionada != null) {
      final servicos = item['servicos_desejados'];
      final especializacao = dadosUsuario?['especializacao'];

      final encontrouNaDemanda =
          _listaContemFiltro(servicos, _profissaoSelecionada);
      final encontrouNoPerfil =
          _listaContemFiltro(especializacao, _profissaoSelecionada) ||
              _textoFiltroContem(especializacao, _profissaoSelecionada);

      if (!encontrouNaDemanda && !encontrouNoPerfil) {
        return false;
      }
    }

    if (_servicoSelecionado != null) {
      final servicos = item['servicos_desejados'];
      final especializacao = dadosUsuario?['especializacao'];

      final encontrouNaDemanda =
          _listaContemFiltro(servicos, _servicoSelecionado);
      final encontrouNoPerfil =
          _listaContemFiltro(especializacao, _servicoSelecionado) ||
              _textoFiltroContem(especializacao, _servicoSelecionado);

      if (!encontrouNaDemanda && !encontrouNoPerfil) {
        return false;
      }
    }

    if (_filtroEstadoSelecionado != null) {
      final estado = dadosUsuario?['estado'] ?? item['estado'];
      if (!_textoFiltroIgual(estado, _filtroEstadoSelecionado)) {
        return false;
      }
    }

    if (_filtroCidadeSelecionada != null) {
      final cidade = dadosUsuario?['cidade'] ?? item['cidade'];
      if (!_textoFiltroIgual(cidade, _filtroCidadeSelecionada)) {
        return false;
      }
    }

    if (_filtroNomePesquisado != null &&
        _filtroNomePesquisado!.trim().isNotEmpty) {
      final nome = dadosUsuario?['usuario_nome'] ??
          dadosUsuario?['nome'] ??
          item['usuario_nome'] ??
          item['nome'] ??
          '';

      if (!_textoFiltroContem(nome, _filtroNomePesquisado)) {
        return false;
      }
    }

    return true;
  }

  Future<List<Map<String, dynamic>>> _buscarDemandas() async {
    final supabase = Supabase.instance.client;
    final meuId = supabase.auth.currentUser?.id;

    bool mostraPerfilFeed = false;
    try {
      final config = await supabase
          .from('tab_configuracoes')
          .select('mostra_perfil_feed')
          .maybeSingle();

      if (config != null && config['mostra_perfil_feed'] == true) {
        mostraPerfilFeed = true;
      }
    } catch (e) {
      debugPrint("Erro ao verificar tab_configuracoes: $e");
    }

    // Busca a base completa e aplica os filtros de forma uniforme depois.
    // Isso evita perder registros por diferença entre campos da demanda
    // e campos do perfil do usuário.
    final response = await supabase
        .from('tab_demandas_clientes')
        .select(
            '*, tab_usuarios(id, usuario_nome, whatsapp, foto_url, usuario_tipo, especializacao, cidade, estado, tab_selo_verificacao(status))')
        .order('id', ascending: false);

    List<Map<String, dynamic>> demandas =
        List<Map<String, dynamic>>.from(response as List);

    // Nunca mostra o próprio usuário no feed.
    if (meuId != null && meuId.isNotEmpty) {
      demandas = demandas.where((d) {
        final dadosUsuario = _extrairDadosUsuario(d['tab_usuarios']);
        final donoId = d['usuario_id'] ??
            d['cliente_id'] ??
            d['user_id'] ??
            dadosUsuario?['id'];
        return donoId != meuId;
      }).toList();
    }

    // Quando configurado, acrescenta os cards de perfil ANTES dos filtros.
    // Assim Nome, Tipo, Profissão, Serviço e Localização também funcionam
    // corretamente para os cards de perfil.
    if (mostraPerfilFeed) {
      try {
        final usuariosResponse = await supabase
            .from('tab_usuarios')
            .select('*, tab_selo_verificacao(status)')
            .order('id', ascending: false);

        final listaUsuarios =
            List<Map<String, dynamic>>.from(usuariosResponse as List);

        for (final u in listaUsuarios) {
          if (meuId != null && u['id'] == meuId) continue;

          demandas.add({
            'is_perfil_card': true,
            'dados_perfil': u,
            'cidade': u['cidade'],
            'estado': u['estado'],
          });
        }
      } catch (e) {
        debugPrint("Erro ao buscar usuários para exibição no feed: $e");
      }
    }

    // Um único ponto de filtragem para demandas e perfis.
    demandas = demandas.where(_itemPassaNosFiltros).toList();

    // Sem filtro explícito de localização, mantém a prioridade:
    // mesma cidade -> mesmo estado -> demais localidades.
    if (_filtroCidadeSelecionada == null && _filtroEstadoSelecionado == null) {
      demandas.sort((a, b) {
        final camadaA = _calcularCamada(a);
        final camadaB = _calcularCamada(b);
        return camadaB.compareTo(camadaA);
      });
    }

    return demandas;
  }

  Widget _buildDestaqueCardPlaceholder(String texto) {
    return Container(
      width: 110,
      margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
      decoration: BoxDecoration(
        color: const Color(0xFF253c59),
        borderRadius: BorderRadius.circular(12),
        border:
            Border.all(color: const Color(0xFFFF8C00).withValues(alpha: 0.5)),
      ),
      child: Center(
          child: Text(texto,
              style: const TextStyle(color: Colors.white54, fontSize: 12))),
    );
  }

  Widget _buildDestaqueCardReal(
      BuildContext context, Map<String, dynamic> demanda) {
    final dadosUsuario = _extrairDadosUsuario(demanda['tab_usuarios']);
    final nomeCliente = dadosUsuario?['usuario_nome'] ?? 'Destaque';
    final fotoUrl = dadosUsuario?['foto_url'];
    final papel = _obterPapelAutor(dadosUsuario);
    final bool isVerificado = _checarUsuarioVerificado(dadosUsuario);

    return GestureDetector(
      onTap: () {
        _abrirDetalhesDemanda(context, demanda, dadosUsuario);
      },
      child: Container(
        width: 120,
        margin: const EdgeInsets.symmetric(horizontal: 8, vertical: 8),
        padding: const EdgeInsets.all(8),
        decoration: BoxDecoration(
          color: const Color(0xFF253c59),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFFF8C00), width: 1.5),
        ),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Stack(
              children: [
                CircleAvatar(
                  radius: 26,
                  backgroundColor: Colors.white12,
                  backgroundImage:
                      (fotoUrl != null && fotoUrl.toString().trim().isNotEmpty)
                          ? NetworkImage(fotoUrl)
                          : null,
                  child: (fotoUrl == null || fotoUrl.toString().trim().isEmpty)
                      ? const Icon(Icons.person,
                          color: Colors.white54, size: 28)
                      : null,
                ),
                Positioned(
                  bottom: 0,
                  right: 0,
                  child: Container(
                    padding: const EdgeInsets.all(2),
                    decoration: const BoxDecoration(
                        color: Color(0xFFFF8C00), shape: BoxShape.circle),
                    child:
                        const Icon(Icons.star, size: 10, color: Colors.white),
                  ),
                ),
                if (isVerificado)
                  Positioned(
                    top: 0,
                    right: 0,
                    child: Container(
                      padding: const EdgeInsets.all(2),
                      decoration: const BoxDecoration(
                        color: Color(0xFF253c59),
                        shape: BoxShape.circle,
                      ),
                      child: const Icon(
                        Icons.verified,
                        color: Colors.blue,
                        size: 14,
                      ),
                    ),
                  ),
              ],
            ),
            const SizedBox(height: 6),
            Text(nomeCliente,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(
                    color: Colors.white,
                    fontSize: 12,
                    fontWeight: FontWeight.bold)),
            const SizedBox(height: 2),
            Text(papel,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: const TextStyle(color: Color(0xFFFF8C00), fontSize: 10)),
          ],
        ),
      ),
    );
  }

  // ============================================================
  // DENUNCIAS DE PERFIS - ACHE OBRA
  // ============================================================
  Widget _botaoDenunciarPerfil(String? usuarioId, String nome) {
    if (usuarioId == null ||
        usuarioId.isEmpty ||
        usuarioId == Supabase.instance.client.auth.currentUser?.id) {
      return const SizedBox.shrink();
    }
    return PopupMenuButton<String>(
      tooltip: 'Opções do perfil',
      icon: const Icon(Icons.more_vert, color: Colors.white54, size: 20),
      padding: EdgeInsets.zero,
      constraints: const BoxConstraints(minWidth: 190),
      color: const Color(0xFF1A2C42),
      onSelected: (opcao) {
        if (opcao == 'denunciar') {
          _abrirDialogoDenuncia(usuarioId, nome);
        }
      },
      itemBuilder: (_) => const [
        PopupMenuItem<String>(
          value: 'denunciar',
          child: Row(
            children: [
              Icon(Icons.flag_outlined, color: Color(0xFFFF8C00), size: 19),
              SizedBox(width: 10),
              Text('Denunciar perfil', style: TextStyle(color: Colors.white)),
            ],
          ),
        ),
      ],
    );
  }

  Future<void> _abrirDialogoDenuncia(String denunciadoId, String nome) async {
    final usuarioAtual = Supabase.instance.client.auth.currentUser;
    if (usuarioAtual == null) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
        content: Text('Entre na sua conta para denunciar um perfil.'),
      ));
      return;
    }
    if (usuarioAtual.id == denunciadoId) return;

    const motivos = <String, String>{
      'perfil_falso': 'Perfil falso',
      'golpe_fraude': 'Golpe ou fraude',
      'conteudo_improprio': 'Conteúdo impróprio',
      'assedio': 'Assédio',
      'informacoes_falsas': 'Informações falsas',
      'spam': 'Spam',
      'outro': 'Outro motivo',
    };
    String? motivoSelecionado;
    bool enviando = false;
    final descricaoController = TextEditingController();
    try {
      if (!mounted) return;
      await showDialog<void>(
        context: context,
        barrierDismissible: false,
        builder: (dialogContext) => StatefulBuilder(
          builder: (dialogContext, atualizarDialogo) => AlertDialog(
            backgroundColor: const Color(0xFF1A2C42),
            shape:
                RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
            title: const Row(children: [
              Icon(Icons.flag_outlined, color: Color(0xFFFF8C00)),
              SizedBox(width: 8),
              Expanded(
                  child: Text('Denunciar perfil',
                      style: TextStyle(color: Colors.white, fontSize: 18))),
            ]),
            content: SingleChildScrollView(
              child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text('Perfil: $nome',
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                        style: const TextStyle(color: Colors.white70)),
                    const SizedBox(height: 16),
                    DropdownButtonFormField<String>(
                      initialValue: motivoSelecionado,
                      isExpanded: true,
                      dropdownColor: const Color(0xFF253C59),
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Motivo da denúncia',
                        labelStyle: TextStyle(color: Colors.white70),
                        enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: Colors.white38)),
                        focusedBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: Color(0xFFFF8C00))),
                      ),
                      items: motivos.entries
                          .map((item) => DropdownMenuItem<String>(
                                value: item.key,
                                child: Text(item.value),
                              ))
                          .toList(),
                      onChanged: enviando
                          ? null
                          : (valor) =>
                              atualizarDialogo(() => motivoSelecionado = valor),
                    ),
                    const SizedBox(height: 14),
                    TextField(
                      controller: descricaoController,
                      enabled: !enviando,
                      maxLines: 3,
                      maxLength: 1000,
                      style: const TextStyle(color: Colors.white),
                      decoration: const InputDecoration(
                        labelText: 'Detalhes (opcional)',
                        hintText: 'Conte o que aconteceu...',
                        hintStyle: TextStyle(color: Colors.white38),
                        labelStyle: TextStyle(color: Colors.white70),
                        enabledBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: Colors.white38)),
                        focusedBorder: OutlineInputBorder(
                            borderSide: BorderSide(color: Color(0xFFFF8C00))),
                      ),
                    ),
                    const Text('A denúncia será encaminhada para análise.',
                        style: TextStyle(color: Colors.white54, fontSize: 12)),
                  ]),
            ),
            actions: [
              TextButton(
                onPressed: enviando ? null : () => Navigator.pop(dialogContext),
                child: const Text('Cancelar',
                    style: TextStyle(color: Colors.white70)),
              ),
              ElevatedButton(
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFFF8C00),
                    foregroundColor: Colors.white),
                onPressed: enviando
                    ? null
                    : () async {
                        if (motivoSelecionado == null) {
                          ScaffoldMessenger.of(context)
                              .showSnackBar(const SnackBar(
                            content: Text('Selecione o motivo da denúncia.'),
                          ));
                          return;
                        }
                        atualizarDialogo(() => enviando = true);
                        try {
                          final idAtual =
                              Supabase.instance.client.auth.currentUser?.id;
                          if (idAtual == null || idAtual == denunciadoId) {
                            throw StateError(
                                'Sessão inválida para enviar denúncia.');
                          }
                          await Supabase.instance.client
                              .from('tab_denuncias_perfis')
                              .insert({
                            'denunciante_id': idAtual,
                            'denunciado_id': denunciadoId,
                            'motivo': motivoSelecionado!,
                            'descricao': descricaoController.text.trim().isEmpty
                                ? null
                                : descricaoController.text.trim(),
                          });
                          if (dialogContext.mounted)
                            Navigator.pop(dialogContext);
                          if (mounted) {
                            ScaffoldMessenger.of(context)
                                .showSnackBar(const SnackBar(
                              content: Text(
                                  'Denúncia enviada para análise. Obrigado!'),
                              backgroundColor: Colors.green,
                            ));
                          }
                        } catch (erro) {
                          debugPrint(
                              'Erro ao enviar denúncia de perfil: $erro');
                          if (mounted) {
                            ScaffoldMessenger.of(context)
                                .showSnackBar(const SnackBar(
                              content: Text(
                                  'Não foi possível enviar a denúncia. Tente novamente.'),
                              backgroundColor: Colors.redAccent,
                            ));
                          }
                        } finally {
                          if (dialogContext.mounted) {
                            atualizarDialogo(() => enviando = false);
                          }
                        }
                      },
                child: enviando
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(
                            strokeWidth: 2, color: Colors.white))
                    : const Text('Enviar denúncia'),
              ),
            ],
          ),
        ),
      );
    } finally {
      // Aguarda o fechamento completo do diálogo antes de liberar o controller.
      WidgetsBinding.instance
          .addPostFrameCallback((_) => descricaoController.dispose());
    }
  }

  Widget _buildPerfilUsuarioCard(
      BuildContext context, Map<String, dynamic> usuario) {
    final nome =
        usuario['usuario_nome'] ?? usuario['nome'] ?? 'Nome não informado';
    final fotoUrl = usuario['foto_url'];
    final userId = usuario['id']?.toString();

    final tipoUsuario = (usuario['usuario_tipo'] ??
            usuario['tipo'] ??
            usuario['perfil'] ??
            'USUÁRIO')
        .toString()
        .trim();

    final especializacao = (usuario['especializacao'] ?? '').toString().trim();

    final cidade = usuario['cidade']?.toString().trim() ?? '';
    final estado = usuario['estado']?.toString().trim() ?? '';
    final bool isVerificado = _checarUsuarioVerificado(usuario);

    String localizacao =
        [cidade, estado].where((e) => e.isNotEmpty).join(' - ');

    return Container(
      margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: const Color(0xFF253c59),
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: Colors.white12),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            crossAxisAlignment: CrossAxisAlignment.center,
            children: [
              GestureDetector(
                onTap: (fotoUrl != null && fotoUrl.toString().trim().isNotEmpty)
                    ? () => _abrirVisualizadorFotos(
                        context, [fotoUrl.toString().trim()], 0)
                    : null,
                child: Stack(
                  children: [
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: Colors.white12,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: fotoUrl != null &&
                                fotoUrl.toString().trim().isNotEmpty
                            ? Image.network(
                                fotoUrl.toString().trim(),
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) =>
                                    const Icon(Icons.person,
                                        color: Colors.white54, size: 30),
                              )
                            : const Icon(Icons.person,
                                color: Colors.white54, size: 30),
                      ),
                    ),
                    if (isVerificado)
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: const BoxDecoration(
                            color: Color(0xFF253c59),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.verified,
                            color: Colors.blue,
                            size: 18,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      nome,
                      style: const TextStyle(
                        color: Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(height: 4),
                    Wrap(
                      spacing: 6,
                      runSpacing: 4,
                      children: [
                        if (tipoUsuario.isNotEmpty)
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: const Color(0xFFFF8C00)
                                  .withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                              border:
                                  Border.all(color: const Color(0xFFFF8C00)),
                            ),
                            child: Text(
                              tipoUsuario.toUpperCase(),
                              style: const TextStyle(
                                color: Color(0xFFFF8C00),
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                        if (especializacao.isNotEmpty &&
                            especializacao.toLowerCase() !=
                                tipoUsuario.toLowerCase())
                          Container(
                            padding: const EdgeInsets.symmetric(
                                horizontal: 8, vertical: 2),
                            decoration: BoxDecoration(
                              color: Colors.blueAccent.withValues(alpha: 0.2),
                              borderRadius: BorderRadius.circular(4),
                              border: Border.all(color: Colors.blueAccent),
                            ),
                            child: Text(
                              especializacao.toUpperCase(),
                              style: const TextStyle(
                                color: Colors.lightBlueAccent,
                                fontSize: 11,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                      ],
                    ),
                    if (localizacao.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          const Icon(Icons.location_on,
                              color: Color(0xFFFF8C00), size: 14),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              localizacao,
                              style: const TextStyle(
                                  color: Colors.white54, fontSize: 12),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
              _botaoDenunciarPerfil(userId, nome.toString()),
            ],
          ),
          const Divider(color: Colors.white12, height: 20),
          _buildSecaoAvaliacaoCard(userId,
              nomePrestador: nome, exibirBotaoComentarios: false),
        ],
      ),
    );
  }

  Widget _buildServicoCard(BuildContext context, Map<String, dynamic> demanda) {
    final descricao = demanda['descricao_detalhada'] ?? 'Sem descrição';
    final dadosUsuario = _extrairDadosUsuario(demanda['tab_usuarios']);

    final cidade = dadosUsuario?['cidade'] ?? demanda['cidade'] ?? '';
    final estado = dadosUsuario?['estado'] ?? demanda['estado'] ?? '';
    final bairro = demanda['bairro'] ?? '';

    final nomeCliente = dadosUsuario?['usuario_nome'] ?? 'Cliente';
    final fotoUrl = dadosUsuario?['foto_url'];
    final targetUserId = dadosUsuario?['id'] ??
        demanda['usuario_id'] ??
        demanda['cliente_id'] ??
        demanda['user_id'];

    final papelAutor = _obterPapelAutor(dadosUsuario);
    final isCliente = papelAutor == 'CLIENTE';
    final subTexto =
        isCliente ? '(Procuro Profissional)' : '(Disponível p/ trabalho)';

    final bool isVerificado = _checarUsuarioVerificado(dadosUsuario);

    List<dynamic> servicos = [];
    if (demanda['servicos_desejados'] != null) {
      servicos = demanda['servicos_desejados'] as List<dynamic>;
    }

    String localizacao = [bairro, cidade, estado]
        .where((e) => e != null && e.toString().trim().isNotEmpty)
        .join(' - ');

    return GestureDetector(
      onTap: () {
        _abrirDetalhesDemanda(context, demanda, dadosUsuario);
      },
      child: Container(
        margin: const EdgeInsets.symmetric(vertical: 8, horizontal: 16),
        padding: const EdgeInsets.all(16),
        decoration: BoxDecoration(
          color: const Color(0xFF253c59),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: Colors.white12),
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Stack(
                  children: [
                    Container(
                      width: 60,
                      height: 60,
                      decoration: BoxDecoration(
                        color: Colors.white12,
                        borderRadius: BorderRadius.circular(8),
                        border: Border.all(color: Colors.white24),
                      ),
                      child: ClipRRect(
                        borderRadius: BorderRadius.circular(8),
                        child: fotoUrl != null &&
                                fotoUrl.toString().trim().isNotEmpty
                            ? Image.network(fotoUrl,
                                fit: BoxFit.cover,
                                errorBuilder: (context, error, stackTrace) =>
                                    const Icon(Icons.person,
                                        color: Colors.white54, size: 30))
                            : const Icon(Icons.person,
                                color: Colors.white54, size: 30),
                      ),
                    ),
                    if (isVerificado)
                      Positioned(
                        right: 0,
                        bottom: 0,
                        child: Container(
                          padding: const EdgeInsets.all(2),
                          decoration: const BoxDecoration(
                            color: Color(0xFF253c59),
                            shape: BoxShape.circle,
                          ),
                          child: const Icon(
                            Icons.verified,
                            color: Colors.blue,
                            size: 18,
                          ),
                        ),
                      ),
                  ],
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 4),
                        decoration: BoxDecoration(
                          color: const Color(0xFFFF8C00).withValues(alpha: 0.2),
                          borderRadius: BorderRadius.circular(4),
                          border: Border.all(color: const Color(0xFFFF8C00)),
                        ),
                        child: Text(papelAutor,
                            style: const TextStyle(
                                color: Color(0xFFFF8C00),
                                fontSize: 12,
                                fontWeight: FontWeight.bold)),
                      ),
                      const SizedBox(height: 4),
                      Text(subTexto,
                          style: const TextStyle(
                              color: Colors.white,
                              fontSize: 13,
                              fontWeight: FontWeight.bold)),
                      const SizedBox(height: 2),
                      Row(
                        children: [
                          Flexible(
                            child: Text(nomeCliente,
                                style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 12,
                                    fontStyle: FontStyle.italic)),
                          ),
                          if (isVerificado) ...[
                            const SizedBox(width: 4),
                            const Icon(Icons.verified,
                                color: Colors.blue, size: 14),
                          ]
                        ],
                      ),
                    ],
                  ),
                ),
                _botaoDenunciarPerfil(
                    targetUserId?.toString(), nomeCliente.toString()),
              ],
            ),
            const SizedBox(height: 12),
            if (servicos.isNotEmpty) ...[
              Text("Serviços: ${servicos.join(', ')}",
                  style: const TextStyle(
                      color: Colors.white,
                      fontWeight: FontWeight.bold,
                      fontSize: 14)),
              const SizedBox(height: 6),
            ],
            Text(descricao,
                style: const TextStyle(color: Colors.white70, fontSize: 14)),
            if (localizacao.isNotEmpty) ...[
              const SizedBox(height: 10),
              Row(
                children: [
                  const Icon(Icons.location_on,
                      color: Color(0xFFFF8C00), size: 16),
                  const SizedBox(width: 4),
                  Expanded(
                      child: Text(localizacao,
                          style: const TextStyle(
                              color: Colors.white54, fontSize: 12))),
                ],
              ),
            ],
            const Divider(color: Colors.white12, height: 20),
            _buildSecaoAvaliacaoCard(targetUserId,
                nomePrestador: nomeCliente, exibirBotaoComentarios: false),
            const SizedBox(height: 10),
            const Align(
              alignment: Alignment.centerRight,
              child: Text("Clique e Veja Meu Trabalho, Minhas Fotos e Vídeos",
                  style: TextStyle(
                      color: Color(0xFFFF8C00),
                      fontSize: 12,
                      fontWeight: FontWeight.bold)),
            ),
          ],
        ),
      ),
    );
  }

  void _abrirVisualizadorFotos(
      BuildContext context, List<String> fotos, int initialIndex) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (context) =>
            _VisualizadorFotosPage(fotos: fotos, initialIndex: initialIndex),
      ),
    );
  }

  void _abrirDetalhesDemanda(BuildContext context, Map<String, dynamic> demanda,
      Map<String, dynamic>? dadosUsuarioInput) {
    final dadosUsuario =
        dadosUsuarioInput ?? _extrairDadosUsuario(demanda['tab_usuarios']);
    final descricao = demanda['descricao_detalhada'] ?? 'Sem descrição';

    final cidade = dadosUsuario?['cidade'] ?? demanda['cidade'] ?? '';
    final estado = dadosUsuario?['estado'] ?? demanda['estado'] ?? '';
    final bairro = demanda['bairro'] ?? '';

    final nomeCliente = dadosUsuario?['usuario_nome'] ?? 'Cliente';
    final fotoUrl = dadosUsuario?['foto_url'];
    final targetUserId = dadosUsuario?['id'] ??
        demanda['usuario_id'] ??
        demanda['cliente_id'] ??
        demanda['user_id'];

    final papelAutor = _obterPapelAutor(dadosUsuario);
    final isCliente = papelAutor == 'CLIENTE';
    final subTexto =
        isCliente ? '(Procuro Profissional)' : '(Disponível p/ trabalho)';

    final bool isVerificado = _checarUsuarioVerificado(dadosUsuario);
    final especializacao = dadosUsuario?['especializacao']?.toString() ?? '';

    List<dynamic> servicos = [];
    if (demanda['servicos_desejados'] != null) {
      servicos = demanda['servicos_desejados'] as List<dynamic>;
    }

    String localizacao = [bairro, cidade, estado]
        .where((e) => e != null && e.toString().trim().isNotEmpty)
        .join(' - ');

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1A2C42),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(20))),
      builder: (context) {
        return FutureBuilder<Map<String, List<String>>>(
          future: _buscarTodasMidiasUsuario(dadosUsuario, demanda),
          builder: (context, snapshot) {
            List<String> fotosTrabalhos = [];
            List<String> videosTrabalhos = [];

            if (snapshot.hasData) {
              fotosTrabalhos = snapshot.data!['fotos'] ?? [];
              videosTrabalhos = snapshot.data!['videos'] ?? [];
            }

            return DraggableScrollableSheet(
              initialChildSize: 0.85,
              minChildSize: 0.5,
              maxChildSize: 0.95,
              expand: false,
              builder: (context, scrollController) {
                return SingleChildScrollView(
                  controller: scrollController,
                  padding: const EdgeInsets.all(20.0),
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Center(
                        child: Container(
                            width: 40,
                            height: 4,
                            decoration: BoxDecoration(
                                color: Colors.white24,
                                borderRadius: BorderRadius.circular(2))),
                      ),
                      const SizedBox(height: 16),
                      Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          GestureDetector(
                            onTap: (fotoUrl != null &&
                                    fotoUrl.toString().trim().isNotEmpty)
                                ? () => _abrirVisualizadorFotos(
                                    context, [fotoUrl.toString().trim()], 0)
                                : null,
                            child: Stack(
                              children: [
                                Container(
                                  width: 70,
                                  height: 70,
                                  decoration: BoxDecoration(
                                      color: Colors.white12,
                                      borderRadius: BorderRadius.circular(8),
                                      border:
                                          Border.all(color: Colors.white24)),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child: fotoUrl != null &&
                                            fotoUrl.toString().trim().isNotEmpty
                                        ? Image.network(fotoUrl,
                                            fit: BoxFit.cover,
                                            errorBuilder:
                                                (context, error, stackTrace) =>
                                                    const Icon(Icons.person,
                                                        color: Colors.white54,
                                                        size: 35))
                                        : const Icon(Icons.person,
                                            color: Colors.white54, size: 35),
                                  ),
                                ),
                                if (isVerificado)
                                  Positioned(
                                    right: 0,
                                    bottom: 0,
                                    child: Container(
                                      padding: const EdgeInsets.all(2),
                                      decoration: const BoxDecoration(
                                        color: Color(0xFF1A2C42),
                                        shape: BoxShape.circle,
                                      ),
                                      child: const Icon(
                                        Icons.verified,
                                        color: Colors.blue,
                                        size: 20,
                                      ),
                                    ),
                                  ),
                              ],
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 8, vertical: 4),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFFFF8C00)
                                        .withValues(alpha: 0.2),
                                    borderRadius: BorderRadius.circular(4),
                                    border: Border.all(
                                        color: const Color(0xFFFF8C00)),
                                  ),
                                  child: Text(papelAutor,
                                      style: const TextStyle(
                                          color: Color(0xFFFF8C00),
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold)),
                                ),
                                const SizedBox(height: 4),
                                Text(subTexto,
                                    style: const TextStyle(
                                        color: Colors.white,
                                        fontSize: 13,
                                        fontWeight: FontWeight.bold)),
                                const SizedBox(height: 2),
                                Row(
                                  children: [
                                    Flexible(
                                      child: Text(nomeCliente,
                                          style: const TextStyle(
                                              color: Colors.white70,
                                              fontSize: 12,
                                              fontStyle: FontStyle.italic)),
                                    ),
                                    if (isVerificado) ...[
                                      const SizedBox(width: 4),
                                      const Icon(Icons.verified,
                                          color: Colors.blue, size: 14),
                                    ]
                                  ],
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 16),
                      const Divider(color: Colors.white24),
                      const SizedBox(height: 10),
                      _buildSecaoAvaliacaoCard(targetUserId,
                          nomePrestador: nomeCliente,
                          exibirBotaoComentarios: true),
                      const SizedBox(height: 16),
                      if (especializacao.isNotEmpty) ...[
                        const Text("Especialidades / Details:",
                            style: TextStyle(
                                color: Color(0xFFFF8C00),
                                fontWeight: FontWeight.bold,
                                fontSize: 14)),
                        const SizedBox(height: 4),
                        Text(especializacao,
                            style: const TextStyle(
                                color: Colors.white70, fontSize: 14)),
                        const SizedBox(height: 12),
                      ],
                      if (servicos.isNotEmpty) ...[
                        const Text("Serviços Desejados:",
                            style: TextStyle(
                                color: Color(0xFFFF8C00),
                                fontWeight: FontWeight.bold,
                                fontSize: 14)),
                        const SizedBox(height: 4),
                        Text(servicos.join(', '),
                            style: const TextStyle(
                                color: Colors.white, fontSize: 14)),
                        const SizedBox(height: 12),
                      ],
                      const Text("Descrição Detalhada:",
                          style: TextStyle(
                              color: Color(0xFFFF8C00),
                              fontWeight: FontWeight.bold,
                              fontSize: 14)),
                      const SizedBox(height: 4),
                      Text(descricao,
                          style: const TextStyle(
                              color: Colors.white70, fontSize: 14)),
                      if (localizacao.isNotEmpty) ...[
                        const SizedBox(height: 12),
                        const Text("Localização:",
                            style: TextStyle(
                                color: Color(0xFFFF8C00),
                                fontWeight: FontWeight.bold,
                                fontSize: 14)),
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            const Icon(Icons.location_on,
                                color: Color(0xFFFF8C00), size: 16),
                            const SizedBox(width: 4),
                            Expanded(
                                child: Text(localizacao,
                                    style: const TextStyle(
                                        color: Colors.white54, fontSize: 13))),
                          ],
                        ),
                      ],
                      if (fotosTrabalhos.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        const Text("Fotos dos Trabalhos:",
                            style: TextStyle(
                                color: Color(0xFFFF8C00),
                                fontWeight: FontWeight.bold,
                                fontSize: 14)),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 90,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: fotosTrabalhos.length,
                            itemBuilder: (context, index) {
                              final foto = fotosTrabalhos[index];
                              return GestureDetector(
                                onTap: () {
                                  _abrirVisualizadorFotos(
                                      context, fotosTrabalhos, index);
                                },
                                child: Container(
                                  width: 90,
                                  margin: const EdgeInsets.only(right: 8),
                                  decoration: BoxDecoration(
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                        color: const Color(0xFFFF8C00),
                                        width: 1.5),
                                  ),
                                  child: ClipRRect(
                                    borderRadius: BorderRadius.circular(8),
                                    child:
                                        Image.network(foto, fit: BoxFit.cover,
                                            errorBuilder: (ctx, err, stack) {
                                      return const Center(
                                          child: Icon(Icons.broken_image,
                                              color: Colors.white54));
                                    }),
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                      if (videosTrabalhos.isNotEmpty) ...[
                        const SizedBox(height: 16),
                        const Text("Vídeos dos Trabalhos:",
                            style: TextStyle(
                                color: Color(0xFFFF8C00),
                                fontWeight: FontWeight.bold,
                                fontSize: 14)),
                        const SizedBox(height: 8),
                        SizedBox(
                          height: 55,
                          child: ListView.builder(
                            scrollDirection: Axis.horizontal,
                            itemCount: videosTrabalhos.length,
                            itemBuilder: (context, index) {
                              final videoUrl = videosTrabalhos[index];
                              return GestureDetector(
                                onTap: () {
                                  Navigator.push(
                                    context,
                                    MaterialPageRoute(
                                      builder: (context) =>
                                          _VisualizadorVideoPage(
                                              videoUrl: videoUrl),
                                    ),
                                  );
                                },
                                child: Container(
                                  alignment: Alignment.center,
                                  margin: const EdgeInsets.only(right: 8),
                                  padding: const EdgeInsets.symmetric(
                                      horizontal: 14),
                                  decoration: BoxDecoration(
                                    color: const Color(0xFF253c59),
                                    borderRadius: BorderRadius.circular(8),
                                    border: Border.all(
                                        color: const Color(0xFFFF8C00),
                                        width: 1.5),
                                  ),
                                  child: Row(
                                    children: [
                                      const Icon(Icons.play_circle_fill,
                                          color: Color(0xFFFF8C00), size: 26),
                                      const SizedBox(width: 8),
                                      Text("Vídeo ${index + 1}",
                                          style: const TextStyle(
                                              color: Colors.white,
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold)),
                                    ],
                                  ),
                                ),
                              );
                            },
                          ),
                        ),
                      ],
                      const SizedBox(height: 24),
                      SizedBox(
                        width: double.infinity,
                        child: ElevatedButton.icon(
                          onPressed: () {
                            Navigator.pop(context);
                            _iniciarChat(demanda, dadosUsuario);
                          },
                          icon: const Icon(Icons.chat, color: Colors.white),
                          label: const Text("Conversar pelo Chat do App"),
                          style: ElevatedButton.styleFrom(
                            backgroundColor: const Color(0xFFFF8C00),
                            foregroundColor: Colors.white,
                            padding: const EdgeInsets.symmetric(vertical: 12),
                            shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(8)),
                          ),
                        ),
                      ),
                    ],
                  ),
                );
              },
            );
          },
        );
      },
    );
  }
}

class _VisualizadorFotosPage extends StatefulWidget {
  final List<String> fotos;
  final int initialIndex;

  const _VisualizadorFotosPage(
      {required this.fotos, required this.initialIndex});

  @override
  State<_VisualizadorFotosPage> createState() => _VisualizadorFotosPageState();
}

class _VisualizadorFotosPageState extends State<_VisualizadorFotosPage> {
  late PageController _pageController;
  late int _currentIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.initialIndex;
    _pageController = PageController(initialPage: widget.initialIndex);
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: Text(
          "${_currentIndex + 1} de ${widget.fotos.length}",
          style: const TextStyle(color: Colors.white, fontSize: 16),
        ),
      ),
      body: PageView.builder(
        controller: _pageController,
        itemCount: widget.fotos.length,
        onPageChanged: (index) {
          setState(() {
            _currentIndex = index;
          });
        },
        itemBuilder: (context, index) {
          return Center(
            child: InteractiveViewer(
              panEnabled: true,
              boundaryMargin: const EdgeInsets.all(20),
              minScale: 0.5,
              maxScale: 4.0,
              child: Image.network(
                widget.fotos[index],
                fit: BoxFit.contain,
                errorBuilder: (ctx, err, stack) => const Center(
                  child: Text("Erro ao carregar imagem",
                      style: TextStyle(color: Colors.white)),
                ),
              ),
            ),
          );
        },
      ),
    );
  }
}

class _VisualizadorVideoPage extends StatefulWidget {
  final String videoUrl;

  const _VisualizadorVideoPage({required this.videoUrl});

  @override
  State<_VisualizadorVideoPage> createState() => _VisualizadorVideoPageState();
}

class _VisualizadorVideoPageState extends State<_VisualizadorVideoPage> {
  late VideoPlayerController _controller;
  bool _isInitialized = false;

  @override
  void initState() {
    super.initState();
    _controller = VideoPlayerController.networkUrl(Uri.parse(widget.videoUrl))
      ..initialize().then((_) {
        if (mounted) {
          setState(() {
            _isInitialized = true;
          });
          _controller.play();
        }
      });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: Colors.black,
      appBar: AppBar(
        backgroundColor: Colors.black,
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text("Vídeo do Trabalho",
            style: TextStyle(color: Colors.white, fontSize: 16)),
      ),
      body: Center(
        child: _isInitialized
            ? AspectRatio(
                aspectRatio: _controller.value.aspectRatio,
                child: Stack(
                  alignment: Alignment.center,
                  children: [
                    VideoPlayer(_controller),
                    GestureDetector(
                      onTap: () {
                        setState(() {
                          if (_controller.value.isPlaying) {
                            _controller.pause();
                          } else {
                            _controller.play();
                          }
                        });
                      },
                      child: Container(
                        color: Colors.transparent,
                        child: Center(
                          child: Icon(
                            _controller.value.isPlaying
                                ? Icons.pause_circle_filled
                                : Icons.play_circle_filled,
                            color: Colors.white.withValues(alpha: 0.7),
                            size: 64,
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              )
            : const CircularProgressIndicator(color: Color(0xFFFF8C00)),
      ),
    );
  }
}

class MinhaContaPage extends StatefulWidget {
  const MinhaContaPage({super.key});

  @override
  State<MinhaContaPage> createState() => _MinhaContaPageState();
}

class _MinhaContaPageState extends State<MinhaContaPage> {
  bool _carregando = false;

  Future<void> _confirmarEInativar() async {
    final supabase = Supabase.instance.client;
    final user = supabase.auth.currentUser;

    if (user == null || user.email == null) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content:
                Text('Erro crítico: Nenhum usuário autenticado na sessão!'),
            backgroundColor: Colors.red,
          ),
        );
      }
      return;
    }

    final senhaController = TextEditingController();
    bool obscurePassword = true;

    bool? senhaConfirmada = await showDialog<bool>(
      context: context,
      builder: (context) => StatefulBuilder(
        builder: (context, setStateDialog) => AlertDialog(
          backgroundColor: const Color(0xFF253c59),
          title: const Text('Excluir Conta',
              style: TextStyle(color: Colors.white)),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              const Text(
                'DESEJA REALMENTE EXCLUIR A CONTA E PERDER AS SUAS VANTAGENS?\n\n'
                'Após sua conta ser desativada, seus dados ficarão salvos por 30 dias em nosso sistema, após isso serão apagados permanentemente.\n\n'
                'Para sua segurança, digite sua senha atual:',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 14,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 16),
              TextField(
                controller: senhaController,
                obscureText: obscurePassword,
                style: const TextStyle(color: Colors.white),
                decoration: InputDecoration(
                  labelText: 'Sua Senha',
                  labelStyle: const TextStyle(color: Colors.white54),
                  enabledBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.white24),
                  ),
                  focusedBorder: const OutlineInputBorder(
                    borderSide: BorderSide(color: Colors.amber),
                  ),
                  suffixIcon: IconButton(
                    icon: Icon(
                      obscurePassword ? Icons.visibility_off : Icons.visibility,
                      color: Colors.white54,
                    ),
                    onPressed: () {
                      setStateDialog(() {
                        obscurePassword = !obscurePassword;
                      });
                    },
                  ),
                ),
              ),
            ],
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(context, false),
              child: const Text('Não', style: TextStyle(color: Colors.white54)),
            ),
            TextButton(
              onPressed: () => Navigator.pop(context, true),
              child:
                  const Text('Sim', style: TextStyle(color: Colors.redAccent)),
            ),
          ],
        ),
      ),
    );

    if (senhaConfirmada != true) return;

    final senhaDigitada = senhaController.text.trim();
    if (senhaDigitada.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('A senha é obrigatória para confirmar a exclusão.'),
            backgroundColor: Colors.redAccent,
          ),
        );
      }
      return;
    }

    setState(() => _carregando = true);
    try {
      await supabase.auth.signInWithPassword(
        email: user.email!,
        password: senhaDigitada,
      );
    } catch (e) {
      setState(() => _carregando = false);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Senha incorreta ou erro de validação: $e'),
            backgroundColor: Colors.redAccent,
            duration: const Duration(seconds: 5),
          ),
        );
      }
      return;
    }

    await _executarInativacaoFinal();
  }

  Future<void> _executarInativacaoFinal() async {
    setState(() {
      _carregando = true;
    });

    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;

      if (user == null) throw "Usuário não autenticado.";

      await supabase
          .from('tab_usuarios')
          .update({'usuario_status': 'inativo'}).eq('id', user.id);

      await supabase.auth.signOut();

      if (mounted) {
        Navigator.of(context).pushAndRemoveUntil(
          MaterialPageRoute(builder: (context) => const AcheObraHome()),
          (route) => false,
        );
      }
    } catch (e) {
      setState(() => _carregando = false);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('Erro ao inativar conta: $e'),
            backgroundColor: Colors.redAccent,
            duration: const Duration(seconds: 8),
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A2C42),
      appBar: AppBar(
        backgroundColor: const Color(0xFF101B2B),
        title: const Text(
          'Minha Conta',
          style: TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: Stack(
        children: [
          Padding(
            padding: const EdgeInsets.all(24.0),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text(
                  'Gerenciamento de Conta',
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                const SizedBox(height: 10),
                const Text(
                  'Gerencie suas preferências de acesso. A exclusão desativará sua conta permanentemente no sistema.\n\n'
                  'Atenção: Após sua conta ser desativada, seus dados ficarão salvos por 30 dias em nosso sistema, após isso serão apagados permanentemente.',
                  style: TextStyle(
                      color: Colors.white70, fontSize: 14, height: 1.4),
                ),
                const Spacer(),
                SizedBox(
                  width: double.infinity,
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      side: const BorderSide(color: Colors.redAccent),
                      padding: const EdgeInsets.symmetric(vertical: 14),
                      backgroundColor: Colors.red.withValues(alpha: 0.1),
                    ),
                    icon: const Icon(
                      Icons.delete_forever,
                      color: Colors.redAccent,
                    ),
                    onPressed: _confirmarEInativar,
                    label: const Text(
                      'EXCLUIR CONTA',
                      style: TextStyle(
                        color: Colors.redAccent,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
          if (_carregando)
            Container(
              color: Colors.black.withValues(alpha: 0.5),
              child: const Center(
                child: CircularProgressIndicator(
                  color: Color(0xFFFF8C00),
                ),
              ),
            ),
        ],
      ),
    );
  }
}
