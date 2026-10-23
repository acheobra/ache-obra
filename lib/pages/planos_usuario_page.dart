import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import '../widgets/checkout_modal.dart';
import '../widgets/checkout_google.dart';
import '../widgets/checkout_apple_page.dart';

class PlanosUsuarioPage extends StatefulWidget {
  final String? tipoUsuarioLogado;

  const PlanosUsuarioPage({super.key, this.tipoUsuarioLogado});

  @override
  State<PlanosUsuarioPage> createState() => _PlanosUsuarioPageState();
}

class _PlanosUsuarioPageState extends State<PlanosUsuarioPage> {
  // Na distribuição pela Google Play, planos digitais usam exclusivamente
  // o Google Play Billing. A integração EfíPay permanece no projeto para
  // outros canais/usos permitidos, sem ficar acessível nesta distribuição.
  // O valor padrão é true: não é necessário alterar o comando de build.
  // Não habilite a EfíPay para os mesmos bens digitais no app distribuído
  // pela Play Store sem antes atender aos programas/regras aplicáveis.
  static const bool _somenteGooglePlay = bool.fromEnvironment(
    'ACHE_OBRA_SOMENTE_GOOGLE_PLAY',
    defaultValue: true,
  );

  static const String _backendUrl = 'https://efi-backend-1.onrender.com';
  static const String _googleBackendUrl =
      'https://google-backend-e7ti.onrender.com';
  // Configure com a URL pública do serviço apple-backend.
  // Não reutilize o backend Google nem o backend Efí.
  static const String _appleBackendUrl = String.fromEnvironment(
    'ACHE_OBRA_APPLE_BACKEND_URL',
    // URL pública do serviço apple-backend no Render.
    // Pode ser sobrescrita no build usando --dart-define.
    defaultValue: 'https://apple-backend-501w.onrender.com',
  );
  bool _carregando = true;

  // Consulta de preços da App Store. Compras iOS ficam bloqueadas até
  // o backend Apple validar transações com segurança.
  final InAppPurchase _iapApple = InAppPurchase.instance;
  final Map<String, ProductDetails> _produtosApple = {};
  bool _appleDisponivel = false;
  bool _carregandoProdutosApple = false;
  String? _erroProdutosApple;

  bool get _plataformaApple => Platform.isIOS;

  // Impede duas tentativas de compra/troca de plano ao mesmo tempo.
  // Isso evita abrir dois checkouts e gerar duas cobranças por toque repetido.
  bool _processandoSelecaoPlano = false;

  // ============================================================
  // INTERVALO MÍNIMO ENTRE ALTERAÇÕES DE PLANO
  // ============================================================
  // Depois que um plano é ativado, o usuário precisa aguardar
  // 60 segundos antes de iniciar outra alteração de plano.
  //
  // A referência principal é plano_data_ativacao do Supabase.
  // Assim, fechar/reabrir a tela ou o app não zera a espera.
  // O Timer serve apenas para atualizar a contagem local.
  // ============================================================
  static const Duration _intervaloMinimoTrocaPlano = Duration(seconds: 60);
  Timer? _timerIntervaloTrocaPlano;
  int _segundosRestantesTrocaPlano = 0;

  List<Map<String, dynamic>> _planosDisponiveis = [];
  String _tipoRealUsuario = 'Cliente';
  String _planoAtivoUsuario = '';
  dynamic _idPlanoAtivoUsuario;
  bool _recorrenteAtivo = false;
  DateTime? _planoDataAtivacao;

  // ============================================================
  // PLANO MANUAL VIGENTE
  // ============================================================
  // Esta tela continua usando tab_usuarios/tab_planos para todo o fluxo
  // financeiro (compra, renovação e cancelamento). O plano manual é
  // consultado separadamente para identificar qual conjunto de benefícios
  // está vigente, sem alterar ou apagar a contratação paga do usuário.
  Map<String, dynamic>? _planoManualAtivo;

  bool get _temPlanoManualAtivo => _planoManualAtivo != null;

  // ============================================================
  // STATUS DA ASSINATURA RECORRENTE / CARÊNCIA
  // ============================================================
  //
  // A autoridade do status continua sendo o backend + Supabase.
  // O Flutter apenas lê tab_assinaturas e apresenta o estado.
  //
  // ativo
  // pagamento_pendente -> mantém os benefícios durante a carência
  // inadimplente        -> carência encerrada
  // cancelado           -> assinatura encerrada
  // ============================================================

  String _statusAssinatura = '';
  String? _efiSubscriptionId;
  DateTime? _dataFimCarencia;

  // ============================================================
  // STATUS VISUAL DOS PLANOS
  // ============================================================
  //
  // Regra visual:
  // - O plano realmente ativo em tab_usuarios exibe "ATIVO".
  // - Um novo plano que possua assinatura em pagamento_pendente
  //   exibe "PROCESSANDO".
  // - Não exibimos "CANCELADO" nos cards. Após o cancelamento,
  //   o usuário volta ao plano Grátis e ele passa a exibir "ATIVO".
  //
  // Enquanto existir uma assinatura em processamento, esta tela
  // consulta o Supabase periodicamente. Assim que o backend mudar
  // o status no banco, a interface é atualizada automaticamente.
  // ============================================================

  dynamic _idPlanoProcessando;
  String? _efiSubscriptionIdProcessando;
  Timer? _timerMonitoramentoPlanos;
  bool _consultaStatusPlanosEmAndamento = false;

  final Map<dynamic, bool> _escolhaRecorrente = {};

  @override
  void initState() {
    super.initState();

    _identificarTipoECarregarPlanos().then((_) async {
      if (Platform.isIOS) await _carregarProdutosApple();
      await _atualizarStatusVisualPlanos();

      if (mounted) {
        _configurarMonitoramentoPlanos();
      }
    });
  }

  @override
  void dispose() {
    _timerMonitoramentoPlanos?.cancel();
    _timerMonitoramentoPlanos = null;
    _timerIntervaloTrocaPlano?.cancel();
    _timerIntervaloTrocaPlano = null;
    super.dispose();
  }

  DateTime? _parseDataSupabaseUtc(dynamic valor) {
    if (valor == null) return null;
    final textoOriginal = valor.toString().trim();
    if (textoOriginal.isEmpty) return null;

    final possuiTimezone = RegExp(
      r'(Z|[+-]\d{2}:?\d{2})$',
      caseSensitive: false,
    ).hasMatch(textoOriginal);

    final textoParaParse = possuiTimezone ? textoOriginal : '${textoOriginal}Z';
    return DateTime.tryParse(textoParaParse)?.toUtc();
  }

  int _calcularSegundosRestantesTrocaPlano() {
    final ativacao = _planoDataAtivacao;
    if (ativacao == null) return 0;

    final agoraUtc = DateTime.now().toUtc();
    final ativacaoUtc = ativacao.toUtc();
    final decorridosMs = agoraUtc.difference(ativacaoUtc).inMilliseconds;

    if (decorridosMs < 0) {
      return _intervaloMinimoTrocaPlano.inSeconds;
    }

    final intervaloMs = _intervaloMinimoTrocaPlano.inMilliseconds;
    if (decorridosMs >= intervaloMs) return 0;

    final restantes = ((intervaloMs - decorridosMs) / 1000).ceil();
    if (restantes <= 0) return 0;
    if (restantes > _intervaloMinimoTrocaPlano.inSeconds) {
      return _intervaloMinimoTrocaPlano.inSeconds;
    }
    return restantes;
  }

  Future<void> _mostrarDialogPagamentoConfirmado({
    required String nomePlano,
  }) async {
    if (!mounted) {
      return;
    }

    await showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (dialogContext) {
        return PopScope(
          canPop: false,
          child: Dialog(
            backgroundColor: Colors.transparent,
            insetPadding: const EdgeInsets.symmetric(
              horizontal: 26,
              vertical: 24,
            ),
            child: Container(
              width: double.infinity,
              constraints: const BoxConstraints(
                maxWidth: 520,
              ),
              padding: const EdgeInsets.fromLTRB(
                28,
                28,
                28,
                24,
              ),
              decoration: BoxDecoration(
                color: const Color(0xFF14253A),
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: const Color(0xFF54E39A).withValues(alpha: 0.45),
                ),
                boxShadow: [
                  BoxShadow(
                    color: Colors.black.withValues(alpha: 0.35),
                    blurRadius: 24,
                    offset: const Offset(0, 10),
                  ),
                ],
              ),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Align(
                    alignment: Alignment.centerLeft,
                    child: Text(
                      'Pagamento',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 23,
                        fontWeight: FontWeight.w800,
                      ),
                    ),
                  ),
                  const SizedBox(height: 18),
                  Divider(
                    color: Colors.white.withValues(alpha: 0.14),
                    height: 1,
                  ),
                  const SizedBox(height: 28),
                  Container(
                    width: 76,
                    height: 76,
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: const Color(0xFF54E39A),
                        width: 6,
                      ),
                    ),
                    child: const Icon(
                      Icons.check_rounded,
                      color: Color(0xFF54E39A),
                      size: 48,
                    ),
                  ),
                  const SizedBox(height: 24),
                  const Text(
                    'Pagamento Confirmado!',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Color(0xFF54E39A),
                      fontSize: 22,
                      fontWeight: FontWeight.w800,
                    ),
                  ),
                  const SizedBox(height: 14),
                  const Text(
                    'Seu pagamento foi aprovado com sucesso.',
                    textAlign: TextAlign.center,
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 15,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 10),
                  Text(
                    'O plano $nomePlano está ativo e pronto para uso.',
                    textAlign: TextAlign.center,
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 15,
                      height: 1.4,
                    ),
                  ),
                  const SizedBox(height: 28),
                  SizedBox(
                    width: 120,
                    height: 52,
                    child: ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(0xFFFF8C00),
                        foregroundColor: Colors.white,
                        elevation: 0,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(28),
                        ),
                      ),
                      onPressed: () {
                        Navigator.of(dialogContext).pop();
                      },
                      child: const Text(
                        'OK',
                        style: TextStyle(
                          fontSize: 17,
                          fontWeight: FontWeight.w800,
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  void _sincronizarTimerTrocaPlano() {
    final restantes = _calcularSegundosRestantesTrocaPlano();

    _timerIntervaloTrocaPlano?.cancel();
    _timerIntervaloTrocaPlano = null;

    if (mounted && _segundosRestantesTrocaPlano != restantes) {
      setState(() {
        _segundosRestantesTrocaPlano = restantes;
      });
    } else {
      _segundosRestantesTrocaPlano = restantes;
    }

    if (restantes <= 0) {
      return;
    }

    _timerIntervaloTrocaPlano = Timer.periodic(
      const Duration(seconds: 1),
      (timer) {
        if (!mounted) {
          timer.cancel();
          return;
        }

        final novosRestantes = _calcularSegundosRestantesTrocaPlano();

        if (novosRestantes <= 0) {
          timer.cancel();
          _timerIntervaloTrocaPlano = null;

          setState(() {
            _segundosRestantesTrocaPlano = 0;
          });

          // O intervalo terminou silenciosamente.
          // Não exibimos mensagem de "troca liberada" para não estimular
          // uma nova alteração de plano.
          return;
        }

        if (_segundosRestantesTrocaPlano != novosRestantes) {
          setState(() {
            _segundosRestantesTrocaPlano = novosRestantes;
          });
        }
      },
    );
  }

  bool _bloquearTrocaPlanoSeNecessario(
    Map<String, dynamic> plano,
  ) {
    if (_idPlanoAtivoUsuario == null || plano['id'] == null) {
      return false;
    }

    // O próprio plano ativo já tem o botão bloqueado na interface.
    // Esta proteção é somente para uma NOVA alteração.
    if (_idPlanoAtivoUsuario.toString().trim() ==
        plano['id'].toString().trim()) {
      return false;
    }

    final restantes = _calcularSegundosRestantesTrocaPlano();

    if (restantes <= 0) {
      return false;
    }

    _segundosRestantesTrocaPlano = restantes;

    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text(
            'Aguarde $restantes ${restantes == 1 ? 'segundo' : 'segundos'} '
            'para alterar o plano novamente.',
          ),
          backgroundColor: const Color(0xFFFF8C00),
          duration: const Duration(seconds: 4),
        ),
      );

    return true;
  }

  void _configurarMonitoramentoPlanos() {
    _timerMonitoramentoPlanos?.cancel();
    _timerMonitoramentoPlanos = null;

    if (_idPlanoProcessando == null) {
      return;
    }

    _timerMonitoramentoPlanos = Timer.periodic(
      const Duration(seconds: 5),
      (_) async {
        await _atualizarStatusVisualPlanos();
      },
    );
  }

  Future<Map<String, dynamic>?> _buscarAssinaturaPendenteMaisRecente({
    int tentativas = 1,
    Duration intervalo = const Duration(milliseconds: 700),
  }) async {
    final user = Supabase.instance.client.auth.currentUser;

    if (user == null) {
      return null;
    }

    final supabase = Supabase.instance.client;

    final int totalTentativas = tentativas < 1 ? 1 : tentativas;

    for (int tentativa = 1; tentativa <= totalTentativas; tentativa++) {
      try {
        final response = await supabase
            .from('tab_assinaturas')
            .select(
              'efi_subscription_id, plano_id, status_assinatura, '
              'ultimo_status_efi, updated_at, created_at',
            )
            .eq(
              'usuario_id',
              user.id,
            )
            .eq(
              'status_assinatura',
              'pagamento_pendente',
            )
            .order(
              'created_at',
              ascending: false,
            )
            .limit(
              1,
            );

        if (response.isNotEmpty) {
          return Map<String, dynamic>.from(
            response.first,
          );
        }
      } catch (e) {
        debugPrint(
          'Tentativa $tentativa/$totalTentativas ao consultar '
          'assinatura em processamento falhou: $e',
        );
      }

      if (tentativa < totalTentativas) {
        await Future<void>.delayed(
          intervalo,
        );
      }
    }

    return null;
  }

  Future<bool> _confirmarPlanoProcessandoAposCheckout({
    required dynamic planoId,
  }) async {
    // O backend pode terminar de gravar tab_assinaturas alguns
    // instantes depois de o checkout devolver o controle à tela.
    //
    // Por isso, não fazemos apenas uma consulta imediata.
    // Tentamos por alguns segundos antes de concluir que não há
    // assinatura realmente em processamento.
    final assinatura = await _buscarAssinaturaPendenteMaisRecente(
      tentativas: 12,
      intervalo: const Duration(milliseconds: 750),
    );

    if (assinatura == null) {
      debugPrint(
        'Nenhuma assinatura pagamento_pendente foi encontrada '
        'após o checkout recorrente.',
      );

      return false;
    }

    final dynamic idPlanoBanco = assinatura['plano_id'];

    if (idPlanoBanco == null) {
      debugPrint(
        'Assinatura pendente encontrada, mas sem plano_id.',
      );

      return false;
    }

    // A assinatura pendente precisa pertencer ao plano que o usuário
    // acabou de tentar assinar. Isso evita marcar outro card antigo
    // como PROCESSANDO caso existam registros de teste anteriores.
    if (idPlanoBanco.toString().trim() != planoId.toString().trim()) {
      debugPrint(
        'Existe assinatura pendente, mas ela pertence a outro plano. '
        'Plano esperado=$planoId | plano banco=$idPlanoBanco',
      );

      return false;
    }

    if (!mounted) {
      return false;
    }

    setState(() {
      _idPlanoProcessando = idPlanoBanco;
      _efiSubscriptionIdProcessando =
          assinatura['efi_subscription_id']?.toString().trim();
    });

    _configurarMonitoramentoPlanos();

    debugPrint(
      'Plano marcado como PROCESSANDO. '
      'plano_id=$idPlanoBanco '
      '| subscription=${_efiSubscriptionIdProcessando ?? '-'}',
    );

    return true;
  }

  Future<void> _atualizarStatusVisualPlanos() async {
    if (_consultaStatusPlanosEmAndamento) {
      return;
    }

    final user = Supabase.instance.client.auth.currentUser;

    if (user == null) {
      return;
    }

    _consultaStatusPlanosEmAndamento = true;

    try {
      // Guarda o estado anterior para detectar quando uma assinatura
      // deixa de estar "pagamento_pendente".
      final String? planoProcessandoAnterior = _idPlanoProcessando?.toString();

      final assinatura = await _buscarAssinaturaPendenteMaisRecente();

      dynamic novoIdPlanoProcessando;
      String? novaSubscriptionProcessando;

      if (assinatura != null) {
        novoIdPlanoProcessando = assinatura['plano_id'];

        novaSubscriptionProcessando =
            assinatura['efi_subscription_id']?.toString().trim();
      }

      final String? novoPlanoProcessando = novoIdPlanoProcessando?.toString();

      final bool processamentoMudou =
          planoProcessandoAnterior != novoPlanoProcessando;

      if (mounted) {
        setState(() {
          _idPlanoProcessando = novoIdPlanoProcessando;
          _efiSubscriptionIdProcessando = novaSubscriptionProcessando;
        });
      }

      // Se existia um plano em processamento e ele deixou de existir
      // como pagamento_pendente, pode ter sido ativado ou encerrado.
      // Recarregamos tab_usuarios para descobrir imediatamente qual é
      // o plano atual verdadeiro e redesenhar os cards.
      if (planoProcessandoAnterior != null && novoPlanoProcessando == null) {
        await _identificarTipoECarregarPlanos();
      } else if (processamentoMudou && mounted) {
        // Mudou de um plano pendente para outro. Mantém a lista, mas
        // garante que o novo card seja redesenhado imediatamente.
        setState(() {});
      }
    } catch (e) {
      debugPrint(
        'Erro ao atualizar status visual dos planos: $e',
      );
    } finally {
      _consultaStatusPlanosEmAndamento = false;

      // O bloco finally não deve conter return, pois isso pode
      // interferir no resultado/erro da operação assíncrona.
      // Se a tela já foi descartada, não há interface para atualizar.
      if (mounted) {
        // Mantém polling apenas enquanto há algo em processamento.
        if (_idPlanoProcessando == null) {
          _timerMonitoramentoPlanos?.cancel();
          _timerMonitoramentoPlanos = null;
        } else if (_timerMonitoramentoPlanos == null ||
            !_timerMonitoramentoPlanos!.isActive) {
          _configurarMonitoramentoPlanos();
        }
      }
    }
  }

  bool _planoEstaProcessando(Map<String, dynamic> plano) {
    if (_idPlanoProcessando == null || plano['id'] == null) {
      return false;
    }

    return _idPlanoProcessando.toString().trim() ==
        plano['id'].toString().trim();
  }

  Widget _buildStatusPlano({
    required bool ativo,
    required bool processando,
  }) {
    final bool mostrarProcessando = processando;

    final Color corPrincipal =
        mostrarProcessando ? const Color(0xFFFFA726) : const Color(0xFF54E39A);

    final Color corFundo = mostrarProcessando
        ? const Color(0xFFFFA726).withValues(alpha: 0.12)
        : const Color(0xFF54E39A).withValues(alpha: 0.11);

    final IconData icone = mostrarProcessando
        ? Icons.hourglass_top_rounded
        : Icons.check_circle_outline_rounded;

    final String texto = mostrarProcessando ? 'PROCESSANDO' : 'ATIVO';

    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 11,
        vertical: 7,
      ),
      decoration: BoxDecoration(
        color: corFundo,
        borderRadius: BorderRadius.circular(
          999,
        ),
        border: Border.all(
          color: corPrincipal.withValues(
            alpha: 0.65,
          ),
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icone,
            size: 15,
            color: corPrincipal,
          ),
          const SizedBox(
            width: 6,
          ),
          Text(
            texto,
            style: TextStyle(
              color: corPrincipal,
              fontSize: 10.5,
              fontWeight: FontWeight.w800,
              letterSpacing: 0.8,
            ),
          ),
        ],
      ),
    );
  }

  double _toDouble(dynamic value) {
    if (value == null) return 0.0;
    if (value is num) return value.toDouble();
    return double.tryParse(value.toString().replaceAll(',', '.')) ?? 0.0;
  }

  int _toInt(dynamic value) {
    if (value == null) return 0;
    if (value is num) return value.toInt();
    return int.tryParse(value.toString()) ?? 0;
  }

  bool _toBool(dynamic value) {
    if (value == null) return false;
    if (value is bool) return value;

    final texto = value.toString().trim().toLowerCase();

    return texto == 'true' ||
        texto == '1' ||
        texto == 'sim' ||
        texto == 'yes' ||
        texto == 'ativo';
  }

  bool _isPlanoGratis(Map<String, dynamic> plano) {
    final nomeCompleto = plano['nome_plano']?.toString().toLowerCase() ?? '';

    final double valorAvulso = _toDouble(plano['valor']);

    final double valorRecorrente = _toDouble(plano['valor_recorrente']);

    return nomeCompleto.contains('gratis') ||
        (valorAvulso == 0 && valorRecorrente == 0);
  }

  bool get _pagamentoPendente =>
      _statusAssinatura.trim().toLowerCase() == 'pagamento_pendente';

  bool get _assinaturaInadimplente =>
      _statusAssinatura.trim().toLowerCase() == 'inadimplente';

  bool get _assinaturaCancelada =>
      _statusAssinatura.trim().toLowerCase() == 'cancelado';

  int _diasRestantesCarencia() {
    final fim = _dataFimCarencia;

    if (fim == null) {
      return 0;
    }

    final diferenca = fim.difference(
      DateTime.now(),
    );

    if (diferenca.isNegative || diferenca.inSeconds <= 0) {
      return 0;
    }

    // Arredonda para cima para o usuário não ver "0 dias"
    // quando ainda restam algumas horas de carência.
    final dias = (diferenca.inSeconds / 86400).ceil();

    if (dias < 0) {
      return 0;
    }

    if (dias > 7) {
      return 7;
    }

    return dias;
  }

  String _formatarDataCurta(DateTime? data) {
    if (data == null) {
      return '';
    }

    final local = data.toLocal();

    final dia = local.day.toString().padLeft(
          2,
          '0',
        );

    final mes = local.month.toString().padLeft(
          2,
          '0',
        );

    return '$dia/$mes/${local.year}';
  }

  Future<void> _carregarStatusAssinatura(
    String usuarioId,
  ) async {
    // Sempre limpa o status antes de uma nova leitura para evitar
    // reaproveitar informação antiga ao trocar de plano/usuário.
    _statusAssinatura = '';
    _efiSubscriptionId = null;
    _dataFimCarencia = null;

    if (!_recorrenteAtivo || _idPlanoAtivoUsuario == null) {
      return;
    }

    try {
      final response = await Supabase.instance.client
          .from('tab_assinaturas')
          .select(
            'efi_subscription_id, plano_id, status_assinatura, '
            'data_inicio_inadimplencia, data_fim_carencia, '
            'ultimo_status_efi, updated_at, created_at',
          )
          .eq(
            'usuario_id',
            usuarioId,
          )
          .eq(
            'plano_id',
            _idPlanoAtivoUsuario.toString(),
          )
          .order(
            'created_at',
            ascending: false,
          )
          .limit(
            1,
          );

      if (response.isEmpty) {
        debugPrint(
          'Nenhuma assinatura encontrada em tab_assinaturas '
          'para o plano recorrente atual.',
        );
        return;
      }

      final assinatura = Map<String, dynamic>.from(
        response.first,
      );

      _statusAssinatura =
          assinatura['status_assinatura']?.toString().trim().toLowerCase() ??
              '';

      _efiSubscriptionId = assinatura['efi_subscription_id']?.toString().trim();

      final fimRaw = assinatura['data_fim_carencia'];

      if (fimRaw != null) {
        _dataFimCarencia = DateTime.tryParse(
          fimRaw.toString(),
        );
      }

      debugPrint(
        'Status da assinatura carregado: $_statusAssinatura '
        '| subscription: ${_efiSubscriptionId ?? '-'} '
        '| fim carência: ${_dataFimCarencia?.toIso8601String() ?? '-'}',
      );
    } catch (e) {
      // Não derruba a tela caso exista uma indisponibilidade momentânea.
      // O plano continua sendo carregado por tab_usuarios.
      debugPrint(
        'Erro ao consultar tab_assinaturas: $e',
      );
    }
  }

  Widget _buildAvisoStatusAssinatura() {
    if (!_recorrenteAtivo) {
      return const SizedBox.shrink();
    }

    if (_pagamentoPendente) {
      final diasRestantes = _diasRestantesCarencia();

      final dataLimite = _formatarDataCurta(
        _dataFimCarencia,
      );

      final String textoPrazo;

      if (_dataFimCarencia == null) {
        textoPrazo = 'Seu plano continua ativo durante o período de carência.';
      } else if (diasRestantes > 1) {
        textoPrazo = 'Você ainda tem $diasRestantes dias para regularizar'
            '${dataLimite.isNotEmpty ? ' (até $dataLimite)' : ''}.';
      } else if (diasRestantes == 1) {
        textoPrazo = 'Resta 1 dia para regularizar'
            '${dataLimite.isNotEmpty ? ' (até $dataLimite)' : ''}.';
      } else {
        textoPrazo = 'O prazo de carência chegou ao fim. '
            'Aguarde a atualização do status da assinatura.';
      }

      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(
          14,
        ),
        decoration: BoxDecoration(
          color: Colors.amber.withValues(
            alpha: 0.12,
          ),
          borderRadius: BorderRadius.circular(
            10,
          ),
          border: Border.all(
            color: Colors.amber.withValues(
              alpha: 0.55,
            ),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Icon(
              Icons.warning_amber_rounded,
              color: Colors.amber,
              size: 22,
            ),
            const SizedBox(
              width: 10,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'PAGAMENTO PENDENTE',
                    style: TextStyle(
                      color: Colors.amber,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.7,
                    ),
                  ),
                  const SizedBox(
                    height: 5,
                  ),
                  Text(
                    'Não conseguimos confirmar a renovação da sua assinatura. '
                    '$textoPrazo Durante a carência, seus benefícios permanecem ativos.',
                    style: const TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    if (_assinaturaInadimplente) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(
          14,
        ),
        decoration: BoxDecoration(
          color: Colors.redAccent.withValues(
            alpha: 0.10,
          ),
          borderRadius: BorderRadius.circular(
            10,
          ),
          border: Border.all(
            color: Colors.redAccent.withValues(
              alpha: 0.50,
            ),
          ),
        ),
        child: const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.lock_clock_outlined,
              color: Colors.redAccent,
              size: 22,
            ),
            SizedBox(
              width: 10,
            ),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    'ASSINATURA INADIMPLENTE',
                    style: TextStyle(
                      color: Colors.redAccent,
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                      letterSpacing: 0.7,
                    ),
                  ),
                  SizedBox(
                    height: 5,
                  ),
                  Text(
                    'O período de carência terminou sem confirmação do pagamento. '
                    'Seu plano está com situação de inadimplência. '
                    'Regularize a assinatura para manter os benefícios.',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 12,
                      height: 1.35,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    if (_assinaturaCancelada) {
      return Container(
        width: double.infinity,
        padding: const EdgeInsets.all(
          12,
        ),
        decoration: BoxDecoration(
          color: Colors.white.withValues(
            alpha: 0.05,
          ),
          borderRadius: BorderRadius.circular(
            10,
          ),
          border: Border.all(
            color: Colors.white12,
          ),
        ),
        child: const Text(
          'Esta assinatura recorrente está cancelada.',
          style: TextStyle(
            color: Colors.white60,
            fontSize: 12,
          ),
        ),
      );
    }

    return const SizedBox.shrink();
  }

  bool _podeExibirBotaoCancelar(bool usuarioTemPlanoPago) {
    // Plano manual pode ser cancelado a qualquer momento.
    // Ele não representa uma compra e, portanto, não entra na regra
    // de arrependimento/estorno de 7 dias dos planos avulsos pagos.
    if (_temPlanoManualAtivo) {
      return true;
    }

    if (!usuarioTemPlanoPago) return false;

    // Plano recorrente pode ser cancelado a qualquer momento.
    if (_recorrenteAtivo) {
      return true;
    }

    // Plano avulso:
    // permite cancelamento somente dentro dos 7 dias.
    if (_planoDataAtivacao != null) {
      final int diasPassados =
          DateTime.now().difference(_planoDataAtivacao!).inDays;

      return diasPassados <= 7;
    }

    // Fallback caso não exista data de ativação.
    return true;
  }

  Future<void> _carregarPlanoManualAtivo(String usuarioId) async {
    try {
      final agoraUtc = DateTime.now().toUtc();

      final response = await Supabase.instance.client
          .from('tab_planos_manuais')
          .select('*')
          .eq('usuario_id', usuarioId)
          .order('data_inicio', ascending: false)
          .order('id', ascending: false);

      Map<String, dynamic>? encontrado;

      for (final item in response) {
        final plano = Map<String, dynamic>.from(item);

        final ativo = _toBool(plano['ativo']);
        final status = plano['status']?.toString().trim().toLowerCase() ?? '';
        final statusValido = status.isEmpty ||
            status == 'ativo' ||
            status == 'true' ||
            status == '1';

        if (!ativo || !statusValido) {
          continue;
        }

        final inicio = _parseDataSupabaseUtc(plano['data_inicio']);
        final fim = _parseDataSupabaseUtc(plano['data_fim']);

        // Se houver data de início futura, o plano ainda não entrou em vigor.
        if (inicio != null && inicio.isAfter(agoraUtc)) {
          continue;
        }

        // data_fim é tratada como instante de expiração.
        if (fim != null && !fim.isAfter(agoraUtc)) {
          continue;
        }

        encontrado = plano;
        break;
      }

      if (mounted) {
        setState(() {
          _planoManualAtivo = encontrado;
        });
      } else {
        _planoManualAtivo = encontrado;
      }

      if (encontrado != null) {
        debugPrint(
          'Plano manual vigente encontrado: '
          '${encontrado['nome_plano'] ?? encontrado['tipo_plano'] ?? '-'} '
          '| id=${encontrado['id']} '
          '| validade=${encontrado['data_fim'] ?? '-'}',
        );
      } else {
        debugPrint('Nenhum plano manual vigente para o usuário.');
      }
    } catch (e) {
      // Compatibilidade/segurança: uma falha na tabela manual não interfere
      // no fluxo de planos pagos já existente nesta tela.
      debugPrint('Não foi possível consultar tab_planos_manuais: $e');

      if (mounted) {
        setState(() {
          _planoManualAtivo = null;
        });
      } else {
        _planoManualAtivo = null;
      }
    }
  }

  Widget _buildAvisoPlanoManualAtivo() {
    final plano = _planoManualAtivo;

    if (plano == null) {
      return const SizedBox.shrink();
    }

    final nome = (plano['nome_plano'] ?? plano['tipo_plano'] ?? 'Manual')
        .toString()
        .trim();
    final dataFim = _parseDataSupabaseUtc(plano['data_fim']);
    final validade = _formatarDataCurta(dataFim);

    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: const Color(0xFFFF8C00).withValues(alpha: 0.10),
        borderRadius: BorderRadius.circular(10),
        border: Border.all(
          color: const Color(0xFFFF8C00).withValues(alpha: 0.55),
        ),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const Icon(
            Icons.workspace_premium_outlined,
            color: Color(0xFFFF8C00),
            size: 22,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  'PLANO MANUAL ATIVO: ${nome.isEmpty ? 'Manual' : nome.toUpperCase()}',
                  style: const TextStyle(
                    color: Color(0xFFFF8C00),
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    letterSpacing: 0.6,
                  ),
                ),
                const SizedBox(height: 5),
                Text(
                  validade.isNotEmpty
                      ? 'Os benefícios liberados pelo administrador estão vigentes até $validade. Se você cancelar este plano, sua conta voltará automaticamente para o plano Grátis.'
                      : 'Os benefícios liberados pelo administrador estão vigentes. Se você cancelar este plano, sua conta voltará automaticamente para o plano Grátis.',
                  style: const TextStyle(
                    color: Colors.white70,
                    fontSize: 12,
                    height: 1.35,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Future<void> _identificarTipoECarregarPlanos() async {
    try {
      String tipoEncontrado = '';

      if (widget.tipoUsuarioLogado != null &&
          widget.tipoUsuarioLogado!.trim().isNotEmpty) {
        tipoEncontrado = widget.tipoUsuarioLogado!.trim();
      }

      final user = Supabase.instance.client.auth.currentUser;

      if (user != null) {
        try {
          Map<String, dynamic>? dadosUsuario;

          try {
            dadosUsuario = await Supabase.instance.client
                .from('tab_usuarios')
                .select(
                  'usuario_tipo, nome_plano_ativo, id_plano_atual, plano_id, recorrente, plano_data_ativacao',
                )
                .eq('id', user.id)
                .maybeSingle();
          } catch (_) {
            dadosUsuario = await Supabase.instance.client
                .from('tab_usuarios')
                .select(
                  'usuario_tipo, nome_plano_ativo, id_plano_atual, plano_id, plano_data_ativacao',
                )
                .eq('id', user.id)
                .maybeSingle();
          }

          if (dadosUsuario != null) {
            if (dadosUsuario['usuario_tipo'] != null) {
              tipoEncontrado = dadosUsuario['usuario_tipo'].toString().trim();
            }

            if (dadosUsuario['nome_plano_ativo'] != null) {
              _planoAtivoUsuario = dadosUsuario['nome_plano_ativo']
                  .toString()
                  .trim()
                  .toLowerCase();
            }

            if (dadosUsuario['id_plano_atual'] != null) {
              _idPlanoAtivoUsuario = dadosUsuario['id_plano_atual'];
            } else if (dadosUsuario['plano_id'] != null) {
              _idPlanoAtivoUsuario = dadosUsuario['plano_id'];
            }

            if (dadosUsuario['recorrente'] != null) {
              _recorrenteAtivo = dadosUsuario['recorrente'] as bool;
            }

            if (dadosUsuario['plano_data_ativacao'] != null) {
              _planoDataAtivacao = _parseDataSupabaseUtc(
                dadosUsuario['plano_data_ativacao'],
              );
            } else {
              _planoDataAtivacao = null;
            }

            _sincronizarTimerTrocaPlano();
          }
        } catch (e) {
          debugPrint(
            'Erro ao buscar dados do usuário no banco: $e',
          );
        }

        // Verifica primeiro se existe uma liberação manual vigente.
        // Isso não altera o plano comercial salvo em tab_usuarios.
        await _carregarPlanoManualAtivo(user.id);

        // Consulta a assinatura recorrente atual para saber se está
        // ativa, em carência, inadimplente ou cancelada.
        await _carregarStatusAssinatura(
          user.id,
        );
      }

      if (tipoEncontrado.isNotEmpty) {
        final lower = tipoEncontrado.toLowerCase();

        if (lower.contains('arq')) {
          tipoEncontrado = 'Arquiteto';
        } else if (lower.contains('eng')) {
          tipoEncontrado = 'Engenheiro';
        } else if (lower.contains('profis')) {
          tipoEncontrado = 'Profissional';
        } else {
          tipoEncontrado = 'Cliente';
        }
      }

      if (mounted) {
        setState(() {
          _tipoRealUsuario =
              tipoEncontrado.isNotEmpty ? tipoEncontrado : 'Cliente';
        });
      }

      await _carregarPlanosDoBanco(
        _tipoRealUsuario,
      );

      // Atualiza também o status visual de eventual nova assinatura
      // em processamento, mesmo que ela ainda não seja o plano ativo
      // gravado em tab_usuarios.
      if (!_consultaStatusPlanosEmAndamento) {
        await _atualizarStatusVisualPlanos();
      }
    } catch (e) {
      debugPrint(
        'Erro ao identificar tipo de usuário: $e',
      );

      await _carregarPlanosDoBanco(
        'Cliente',
      );
    }
  }

  Future<void> _carregarPlanosDoBanco(
    String tipoUsuario,
  ) async {
    if (mounted) {
      setState(() {
        _carregando = true;
      });
    }

    try {
      final tipoBusca = tipoUsuario.trim().toLowerCase();

      final response =
          await Supabase.instance.client.from('tab_planos').select();

      final List<Map<String, dynamic>> allPlans =
          List<Map<String, dynamic>>.from(
        response,
      );

      final planoGratisObj = allPlans.firstWhere(
        (p) => _isPlanoGratis(p),
        orElse: () => {},
      );

      final idPlanoGratis = planoGratisObj['id'];

      final bool userTemPlanoPago = _idPlanoAtivoUsuario != null &&
          idPlanoGratis != null &&
          _idPlanoAtivoUsuario.toString() != idPlanoGratis.toString() &&
          !_planoAtivoUsuario.contains(
            'gratis',
          );

      final filtrados = allPlans.where(
        (plano) {
          final tipoBanco =
              plano['tipo_usuario']?.toString().trim().toLowerCase() ?? '';

          final nomePlano =
              plano['nome_plano']?.toString().trim().toLowerCase() ?? '';

          final statusBanco = plano['status'];

          bool tipoOk = false;

          final bool isPlanoGratisAtual = _isPlanoGratis(plano) &&
              _idPlanoAtivoUsuario != null &&
              plano['id'].toString() == _idPlanoAtivoUsuario.toString();

          if (isPlanoGratisAtual) {
            tipoOk = true;
          } else {
            if (tipoBusca.startsWith('client')) {
              tipoOk = tipoBanco.contains('cliente') ||
                  nomePlano.contains(
                    'cliente',
                  );
            } else if (tipoBusca.startsWith(
              'profis',
            )) {
              tipoOk = tipoBanco.contains(
                    'profissional',
                  ) ||
                  tipoBanco.contains(
                    'profissionais',
                  ) ||
                  nomePlano.contains(
                    'profissional',
                  ) ||
                  nomePlano.contains(
                    'profissionais',
                  );
            } else if (tipoBusca.startsWith('arq')) {
              tipoOk = tipoBanco.contains(
                    'arquiteto',
                  ) ||
                  tipoBanco.contains(
                    'arquitetos',
                  ) ||
                  nomePlano.contains(
                    'arquiteto',
                  ) ||
                  nomePlano.contains(
                    'arquitetos',
                  );
            } else if (tipoBusca.startsWith('eng')) {
              tipoOk = tipoBanco.contains(
                    'engenheiro',
                  ) ||
                  tipoBanco.contains(
                    'engenheiros',
                  ) ||
                  nomePlano.contains(
                    'engenheiro',
                  ) ||
                  nomePlano.contains(
                    'engenheiros',
                  );
            } else {
              tipoOk = tipoBanco.contains(
                    tipoBusca,
                  ) ||
                  nomePlano.contains(
                    tipoBusca,
                  );
            }
          }

          bool statusOk = true;

          if (statusBanco != null) {
            final st = statusBanco.toString().trim().toLowerCase();

            if (st == 'inativo' || st == 'false' || st == '0') {
              statusOk = false;
            }
          }

          bool naoEhGratisSeUsuarioPago = true;

          if (userTemPlanoPago && _isPlanoGratis(plano)) {
            naoEhGratisSeUsuarioPago = false;
          }

          return tipoOk && statusOk && naoEhGratisSeUsuarioPago;
        },
      ).toList();

      // ========================================================
      // DEDUPLICAÇÃO
      // ========================================================

      final Map<String, Map<String, dynamic>> porId = {};

      for (final p in filtrados) {
        final idStr = p['id']?.toString() ?? '';

        if (idStr.isNotEmpty && !porId.containsKey(idStr)) {
          porId[idStr] = p;
        }
      }

      List<Map<String, dynamic>> unicos = porId.values.toList();

      // ========================================================
      // DEDUPLICAÇÃO DO PLANO GRÁTIS
      // ========================================================

      final gratisList = unicos
          .where(
            (p) => _isPlanoGratis(p),
          )
          .toList();

      if (gratisList.length > 1) {
        final Map<String, dynamic> melhorGratis = gratisList.firstWhere(
          (p) =>
              _idPlanoAtivoUsuario != null &&
              p['id'].toString() == _idPlanoAtivoUsuario.toString(),
          orElse: () {
            return gratisList.firstWhere(
              (p) {
                final t = p['tipo_usuario']?.toString().toLowerCase() ?? '';

                final n = p['nome_plano']?.toString().toLowerCase() ?? '';

                return t.contains(tipoBusca) || n.contains(tipoBusca);
              },
              orElse: () => gratisList.first,
            );
          },
        );

        unicos.removeWhere(
          (p) => _isPlanoGratis(p),
        );

        unicos.add(
          melhorGratis,
        );
      }

      // ========================================================
      // ORDENA PELO VALOR
      // ========================================================

      unicos.sort(
        (a, b) {
          final valA = _toDouble(a['valor']);

          final valB = _toDouble(b['valor']);

          return valA.compareTo(
            valB,
          );
        },
      );

      if (mounted) {
        setState(() {
          _planosDisponiveis = List<Map<String, dynamic>>.from(
            unicos,
          );

          _carregando = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _carregando = false;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Erro ao carregar planos: $e',
            ),
            backgroundColor: Colors.red,
          ),
        );
      }
    }
  }

  // ============================================================
  // LOCALIZAR PAGAMENTO AVULSO MAIS RECENTE DO USUÁRIO
  // CARTÃO OU PIX
  // ============================================================
  //
  // A compra mais recente é identificada por created_at DESC.
  // Depois priorizamos o registro:
  // 1. do plano atualmente ativo;
  // 2. com origem_tipo = plano_categoria;
  // 3. com status elegível;
  // 4. independentemente de ter sido pago por cartão ou Pix.
  //
  // Isso evita cancelar uma compra antiga quando o usuário possui
  // mais de um pagamento registrado para o mesmo plano.
  // ============================================================

  Future<Map<String, dynamic>?> _buscarPagamentoAvulsoMaisRecente({
    required SupabaseClient supabase,
    required String usuarioId,
    required String planoId,
  }) async {
    final response = await supabase
        .from('tab_pagamentos_avulsos')
        .select(
          'id, usuario_id, origem_tipo, origem_id, tipo_pagamento, '
          'valor, efi_charge_id, pix_txid, pix_e2e_id, status, '
          'data_pagamento, created_at, estorno_solicitado_em, '
          'estorno_concluido_em, motivo_cancelamento',
        )
        .eq(
          'usuario_id',
          usuarioId,
        )
        .order(
          'created_at',
          ascending: false,
        )
        .limit(
          30,
        );

    final List<Map<String, dynamic>> pagamentos =
        List<Map<String, dynamic>>.from(response);

    debugPrint(
      'Pagamentos avulsos encontrados para o usuário: ${pagamentos.length}',
    );

    if (pagamentos.isEmpty) {
      return null;
    }

    const statusElegiveis = <String>{
      'pago',
      'paid',
      'approved',
      'estorno_pendente',
      'estorno_solicitado',
      'estornado',
      'refunded',
    };

    bool pagamentoElegivel(Map<String, dynamic> pagamento) {
      final tipoPagamento =
          pagamento['tipo_pagamento']?.toString().trim().toLowerCase() ?? '';

      final status = pagamento['status']?.toString().trim().toLowerCase() ?? '';

      final tipoValido = tipoPagamento == 'cartao' || tipoPagamento == 'pix';

      return tipoValido && statusElegiveis.contains(status);
    }

    // ----------------------------------------------------------
    // 1. PRIORIDADE: pagamento mais recente exatamente do plano
    // ----------------------------------------------------------

    for (final pagamento in pagamentos) {
      final origemId = pagamento['origem_id']?.toString().trim() ?? '';

      final origemTipo =
          pagamento['origem_tipo']?.toString().trim().toLowerCase() ?? '';

      final mesmoPlano = origemId == planoId;

      final origemPlano = origemTipo.isEmpty || origemTipo == 'plano_categoria';

      if (mesmoPlano && origemPlano && pagamentoElegivel(pagamento)) {
        final tipoPagamento =
            pagamento['tipo_pagamento']?.toString().trim().toLowerCase() ?? '';

        debugPrint(
          'Pagamento avulso mais recente do plano localizado: '
          'id=${pagamento['id']} '
          '| tipo=$tipoPagamento '
          '| charge_id=${pagamento['efi_charge_id']} '
          '| pix_txid=${pagamento['pix_txid']} '
          '| pix_e2e_id=${pagamento['pix_e2e_id']} '
          '| origem_id=$origemId '
          '| status=${pagamento['status']} '
          '| data_pagamento=${pagamento['data_pagamento']} '
          '| created_at=${pagamento['created_at']}',
        );

        return pagamento;
      }
    }

    // ----------------------------------------------------------
    // 2. FALLBACK: pagamento elegível mais recente do usuário
    // ----------------------------------------------------------
    //
    // Mantido para compatibilidade com registros antigos que
    // eventualmente não tenham origem_id/origem_tipo preenchidos.
    // ----------------------------------------------------------

    for (final pagamento in pagamentos) {
      if (pagamentoElegivel(pagamento)) {
        final tipoPagamento =
            pagamento['tipo_pagamento']?.toString().trim().toLowerCase() ?? '';

        debugPrint(
          'Fallback: usando pagamento avulso elegível mais recente: '
          'id=${pagamento['id']} '
          '| tipo=$tipoPagamento '
          '| charge_id=${pagamento['efi_charge_id']} '
          '| pix_txid=${pagamento['pix_txid']} '
          '| pix_e2e_id=${pagamento['pix_e2e_id']} '
          '| origem_id=${pagamento['origem_id']} '
          '| status=${pagamento['status']} '
          '| data_pagamento=${pagamento['data_pagamento']} '
          '| created_at=${pagamento['created_at']}',
        );

        return pagamento;
      }
    }

    return null;
  }

  Future<Map<String, dynamic>?> _buscarCompraGoogleDoPlanoAtivo({
    required SupabaseClient supabase,
    required String usuarioId,
    required String planoId,
  }) async {
    try {
      final response = await supabase
          .from('tab_assinaturas_google')
          .select(
            'id, usuario_id, plano_id, google_product_id, google_base_plan_id, '
            'purchase_token, google_order_id, status_assinatura, '
            'acknowledgement_state, auto_renovacao, data_inicio, data_expiracao, '
            'data_ultimo_pagamento, cancelado_em, created_at, updated_at, '
            'tipo_compra, recorrente',
          )
          .eq('usuario_id', usuarioId)
          .eq('plano_id', planoId)
          .order('created_at', ascending: false)
          .limit(10);

      if (response.isEmpty) {
        return null;
      }

      final registros = List<Map<String, dynamic>>.from(response);

      const statusIgnorados = <String>{
        'cancelado',
        'canceled',
        'cancelled',
        'expirado',
        'expired',
        'estornado',
        'refunded',
      };

      for (final registro in registros) {
        final status =
            registro['status_assinatura']?.toString().trim().toLowerCase() ??
                '';

        if (!statusIgnorados.contains(status)) {
          debugPrint(
            'Compra Google localizada para o plano ativo: '
            'id=${registro['id']} '
            '| product=${registro['google_product_id']} '
            '| tipo=${registro['tipo_compra']} '
            '| recorrente=${registro['recorrente']} '
            '| status=${registro['status_assinatura']}',
          );
          return registro;
        }
      }

      // Se todos os registros Google estiverem encerrados, não existe
      // compra Google elegível para representar o plano atualmente ativo.
      return null;
    } catch (e) {
      debugPrint(
        'Não foi possível consultar tab_assinaturas_google: $e',
      );
      return null;
    }
  }

  Future<Map<String, dynamic>> _cancelarPlanoGoogleNoBackend({
    required String accessToken,
    required String planoId,
    required Map<String, dynamic> compraGoogle,
  }) async {
    final String purchaseToken =
        compraGoogle['purchase_token']?.toString().trim() ?? '';

    final String googleProductId =
        compraGoogle['google_product_id']?.toString().trim() ?? '';

    final String googleBasePlanId =
        compraGoogle['google_base_plan_id']?.toString().trim() ?? '';

    final String tipoCompraBanco =
        compraGoogle['tipo_compra']?.toString().trim().toLowerCase() ?? '';

    final bool recorrenteGoogle = compraGoogle['recorrente'] == true ||
        tipoCompraBanco == 'recorrente' ||
        googleBasePlanId.isNotEmpty;

    if (purchaseToken.isEmpty) {
      throw 'A compra Google Play não possui purchase_token válido.';
    }

    if (googleProductId.isEmpty) {
      throw 'A compra Google Play não possui google_product_id válido.';
    }

    final response = await http
        .post(
          Uri.parse(
            '$_googleBackendUrl/google/cancelar-plano',
          ),
          headers: {
            'Content-Type': 'application/json',
            'Authorization': 'Bearer $accessToken',
          },
          body: jsonEncode({
            'plano_id': planoId,
            'purchase_token': purchaseToken,
            'google_product_id': googleProductId,
            'google_base_plan_id':
                googleBasePlanId.isEmpty ? null : googleBasePlanId,
            'tipo_compra': recorrenteGoogle ? 'recorrente' : 'avulso',
            'recorrente': recorrenteGoogle,
            'motivo':
                'Cancelamento solicitado pelo usuário no aplicativo Ache Obra.',
          }),
        )
        .timeout(
          const Duration(
            seconds: 60,
          ),
        );

    Map<String, dynamic> data = {};

    try {
      final decoded = jsonDecode(response.body);

      if (decoded is Map) {
        data = Map<String, dynamic>.from(decoded);
      }
    } catch (_) {
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw 'O servidor Google retornou uma resposta inválida ao cancelar o plano.';
      }
    }

    if (response.statusCode < 200 || response.statusCode >= 300) {
      dynamic mensagemServidor = data['error'] ??
          data['message'] ??
          data['mensagem'] ??
          'Não foi possível cancelar o plano comprado pela Google Play.';

      if (mensagemServidor is Map || mensagemServidor is List) {
        mensagemServidor = jsonEncode(mensagemServidor);
      }

      throw mensagemServidor.toString();
    }

    if (data['success'] != true) {
      dynamic mensagemServidor = data['error'] ??
          data['message'] ??
          data['mensagem'] ??
          'O Google Backend não confirmou o cancelamento.';

      if (mensagemServidor is Map || mensagemServidor is List) {
        mensagemServidor = jsonEncode(mensagemServidor);
      }

      throw mensagemServidor.toString();
    }

    return data;
  }

  // ============================================================
  // IDENTIFICAÇÃO DO PROVEDOR DO PLANO ATIVO
  // ============================================================
  // O cancelamento não pode ser decidido apenas pela existência de um
  // registro antigo na Google Play. Para o plano atualmente ativo,
  // comparamos os registros elegíveis da Efí e da Google e escolhemos
  // o provedor da contratação mais recente compatível com o tipo atual
  // (recorrente ou avulso).
  // ============================================================

  Future<Map<String, dynamic>?> _buscarAssinaturaEfiDoPlanoAtivo({
    required SupabaseClient supabase,
    required String usuarioId,
    required String planoId,
  }) async {
    try {
      final response = await supabase
          .from('tab_assinaturas')
          .select(
            'id, usuario_id, plano_id, efi_subscription_id, efi_plan_id, '
            'efi_charge_id, status_assinatura, ultimo_status_efi, '
            'created_at, updated_at',
          )
          .eq('usuario_id', usuarioId)
          .eq('plano_id', planoId)
          .order('created_at', ascending: false)
          .limit(20);

      if (response.isEmpty) return null;

      const statusIgnorados = <String>{
        'cancelado',
        'canceled',
        'cancelled',
        'expirado',
        'expired',
        'estornado',
        'refunded',
      };

      for (final item in response) {
        final registro = Map<String, dynamic>.from(item);
        final subscriptionId =
            registro['efi_subscription_id']?.toString().trim() ?? '';
        final status =
            registro['status_assinatura']?.toString().trim().toLowerCase() ??
                '';

        if (subscriptionId.isNotEmpty && !statusIgnorados.contains(status)) {
          debugPrint(
            'Assinatura Efí elegível localizada para o plano ativo: '
            'subscription=$subscriptionId | status=$status',
          );
          return registro;
        }
      }

      return null;
    } catch (e) {
      debugPrint('Não foi possível consultar a assinatura Efí ativa: $e');
      return null;
    }
  }

  DateTime? _dataReferenciaRegistro(Map<String, dynamic>? registro) {
    if (registro == null) return null;

    const campos = <String>[
      'created_at',
      'data_inicio',
      'data_pagamento',
      'updated_at',
    ];

    for (final campo in campos) {
      final valor = registro[campo];
      if (valor == null) continue;
      final data = DateTime.tryParse(valor.toString());
      if (data != null) return data.toUtc();
    }

    return null;
  }

  bool _compraGoogleEhRecorrente(Map<String, dynamic> compraGoogle) {
    final tipoCompra =
        compraGoogle['tipo_compra']?.toString().trim().toLowerCase() ?? '';
    final basePlan =
        compraGoogle['google_base_plan_id']?.toString().trim() ?? '';

    return compraGoogle['recorrente'] == true ||
        tipoCompra == 'recorrente' ||
        basePlan.isNotEmpty;
  }

  String _resolverProvedorPlanoAtivo({
    required bool recorrenteAtual,
    Map<String, dynamic>? assinaturaEfi,
    Map<String, dynamic>? pagamentoEfi,
    Map<String, dynamic>? compraGoogle,
  }) {
    final bool googleRecorrente =
        compraGoogle != null && _compraGoogleEhRecorrente(compraGoogle);

    if (recorrenteAtual) {
      final bool efiElegivel = assinaturaEfi != null;
      final bool googleElegivel = compraGoogle != null && googleRecorrente;

      if (efiElegivel && !googleElegivel) return 'efi';
      if (!efiElegivel && googleElegivel) return 'google';
      if (!efiElegivel && !googleElegivel) return '';

      final dataEfi = _dataReferenciaRegistro(assinaturaEfi);
      final dataGoogle = _dataReferenciaRegistro(compraGoogle);

      if (dataEfi != null && dataGoogle != null) {
        return dataEfi.isAfter(dataGoogle) ? 'efi' : 'google';
      }

      // Havendo uma assinatura Efí válida e sem datas comparáveis,
      // não desviamos o cancelamento para um registro Google histórico.
      return 'efi';
    }

    final bool efiElegivel = pagamentoEfi != null;
    final bool googleElegivel = compraGoogle != null && !googleRecorrente;

    if (efiElegivel && !googleElegivel) return 'efi';
    if (!efiElegivel && googleElegivel) return 'google';
    if (!efiElegivel && !googleElegivel) return '';

    final dataEfi = _dataReferenciaRegistro(pagamentoEfi);
    final dataGoogle = _dataReferenciaRegistro(compraGoogle);

    if (dataEfi != null && dataGoogle != null) {
      return dataEfi.isAfter(dataGoogle) ? 'efi' : 'google';
    }

    // Para avulso, se ambos existirem mas não houver data confiável,
    // preferimos não usar um registro Google antigo para desviar o fluxo Efí.
    return 'efi';
  }

  Future<Map<String, dynamic>> _buscarPlanoGratisDoMesmoTipo({
    required SupabaseClient supabase,
  }) async {
    final responseList = await supabase
        .from('tab_planos')
        .select()
        .ilike('nome_plano', '%gratis%');

    if (responseList.isEmpty) {
      throw 'Nenhum plano Grátis foi encontrado na base de dados.';
    }

    Map<String, dynamic>? responseGratis;
    final tipoRealLower = _tipoRealUsuario.toLowerCase();

    for (final item in responseList) {
      final plano = Map<String, dynamic>.from(item);

      final tipoBanco =
          plano['tipo_usuario']?.toString().trim().toLowerCase() ?? '';

      final nomeBanco =
          plano['nome_plano']?.toString().trim().toLowerCase() ?? '';

      bool pertenceAoTipo = false;

      if (tipoRealLower.startsWith('client')) {
        pertenceAoTipo =
            tipoBanco.contains('cliente') || nomeBanco.contains('cliente');
      } else if (tipoRealLower.startsWith('profis')) {
        pertenceAoTipo = tipoBanco.contains('profissional') ||
            tipoBanco.contains('profissionais') ||
            nomeBanco.contains('profissional') ||
            nomeBanco.contains('profissionais');
      } else if (tipoRealLower.startsWith('arq')) {
        pertenceAoTipo = tipoBanco.contains('arquiteto') ||
            tipoBanco.contains('arquitetos') ||
            nomeBanco.contains('arquiteto') ||
            nomeBanco.contains('arquitetos');
      } else if (tipoRealLower.startsWith('eng')) {
        pertenceAoTipo = tipoBanco.contains('engenheiro') ||
            tipoBanco.contains('engenheiros') ||
            nomeBanco.contains('engenheiro') ||
            nomeBanco.contains('engenheiros');
      } else {
        pertenceAoTipo = tipoBanco.contains(tipoRealLower) ||
            nomeBanco.contains(tipoRealLower);
      }

      if (pertenceAoTipo) {
        responseGratis = plano;
        break;
      }
    }

    return responseGratis ??
        Map<String, dynamic>.from(
          responseList.first,
        );
  }

  Future<void> _cancelarPlanoAssinatura() async {
    final bool? confirmou = await showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (context) {
        return AlertDialog(
          backgroundColor: const Color(0xFF253c59),
          title: Text(
            _temPlanoManualAtivo
                ? 'Cancelar Plano Manual'
                : _recorrenteAtivo
                    ? 'Cancelar Assinatura Recorrente'
                    : 'Cancelar Plano',
            style: const TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Text(
            _temPlanoManualAtivo
                ? 'Tem certeza que deseja cancelar o plano manual? '
                    'Os benefícios concedidos pelo administrador serão encerrados e sua conta voltará automaticamente para o plano Grátis.'
                : _recorrenteAtivo
                    ? 'Tem certeza que deseja cancelar a assinatura recorrente? '
                        'A renovação automática será cancelada no provedor em que a assinatura foi contratada.'
                    : 'Tem certeza que deseja cancelar o plano? '
                        'Se a compra estiver dentro do prazo aplicável, o Ache Obra solicitará '
                        'o cancelamento e eventual estorno ao mesmo provedor utilizado no pagamento.',
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 14,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(
                context,
                false,
              ),
              child: const Text(
                'Voltar',
                style: TextStyle(
                  color: Colors.white54,
                ),
              ),
            ),
            ElevatedButton(
              style: ElevatedButton.styleFrom(
                backgroundColor: Colors.redAccent,
              ),
              onPressed: () => Navigator.pop(
                context,
                true,
              ),
              child: const Text(
                'Sim, Cancelar',
                style: TextStyle(
                  color: Colors.white,
                ),
              ),
            ),
          ],
        );
      },
    );

    if (confirmou != true || !mounted) {
      return;
    }

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (context) => const PopScope(
        canPop: false,
        child: Center(
          child: CircularProgressIndicator(
            color: Color(0xFFFF8C00),
          ),
        ),
      ),
    );

    bool dialogCarregamentoAberto = true;
    final bool eraRecorrente = _recorrenteAtivo;

    String statusCancelamentoAvulso = '';
    String mensagemCancelamentoAvulso = '';
    bool cancelamentoGoogle = false;
    bool googleRecorrente = false;
    String mensagemGoogle = '';

    try {
      final supabase = Supabase.instance.client;
      final user = supabase.auth.currentUser;

      if (user == null) {
        throw 'Usuário não autenticado.';
      }

      final session = supabase.auth.currentSession;

      if (session == null || session.accessToken.trim().isEmpty) {
        throw 'Sua sessão expirou. Entre novamente para cancelar o plano.';
      }

      // ======================================================
      // PLANO MANUAL - TESTE / CORTESIA / PARCERIA / ESPECIAL
      // ======================================================
      // Plano manual não possui cobrança para cancelar ou estornar.
      // Portanto, ele NÃO passa pela regra de 7 dias e NÃO tenta
      // localizar pagamento Efí/Google. Ao cancelar, desativamos a
      // concessão manual e apontamos o usuário diretamente para o
      // plano Grátis da mesma categoria.
      if (_temPlanoManualAtivo) {
        final planoManual = Map<String, dynamic>.from(_planoManualAtivo!);
        final dynamic planoManualId = planoManual['id'];

        if (planoManualId == null) {
          throw 'Não foi possível identificar o plano manual ativo.';
        }

        final responseGratis = await _buscarPlanoGratisDoMesmoTipo(
          supabase: supabase,
        );

        final dynamic idPlanoGratis = responseGratis['id'];

        if (idPlanoGratis == null) {
          throw 'Não foi possível identificar o plano Grátis para este usuário.';
        }

        String nomeCompletoGratis =
            responseGratis['nome_plano']?.toString().trim() ?? 'Grátis';

        String nomeBaseGratis = nomeCompletoGratis;

        if (nomeCompletoGratis.contains('-')) {
          nomeBaseGratis = nomeCompletoGratis.split('-').last.trim();
        }

        final agoraIso = DateTime.now().toUtc().toIso8601String();

        // Encerra somente o plano manual vigente. Mantemos o registro
        // no histórico; ele apenas deixa de estar ativo.
        await supabase.from('tab_planos_manuais').update({
          'ativo': false,
          'status': 'cancelado',
          'data_fim': agoraIso,
        }).eq('id', planoManualId);

        // A regra do Ache Obra é única: cancelou qualquer plano ativo,
        // o usuário volta imediatamente para o plano Grátis.
        try {
          await supabase.from('tab_usuarios').update({
            'nome_plano_ativo': nomeBaseGratis,
            'id_plano_atual': idPlanoGratis,
            'plano_id': idPlanoGratis,
            'recorrente': false,
            'plano_data_ativacao': null,
            'plano_expiracao': null,
          }).eq('id', user.id);
        } catch (_) {
          // Compatibilidade caso alguma versão antiga da tabela ainda
          // não possua recorrente/plano_expiracao.
          await supabase.from('tab_usuarios').update({
            'nome_plano_ativo': nomeBaseGratis,
            'id_plano_atual': idPlanoGratis,
            'plano_id': idPlanoGratis,
            'plano_data_ativacao': null,
          }).eq('id', user.id);
        }

        if (mounted && dialogCarregamentoAberto) {
          Navigator.of(
            context,
            rootNavigator: true,
          ).pop();
          dialogCarregamentoAberto = false;
        }

        if (!mounted) {
          return;
        }

        setState(() {
          _planoManualAtivo = null;
          _planoAtivoUsuario = nomeBaseGratis.toLowerCase();
          _idPlanoAtivoUsuario = idPlanoGratis;
          _recorrenteAtivo = false;
          _planoDataAtivacao = null;
          _statusAssinatura = '';
          _efiSubscriptionId = null;
          _dataFimCarencia = null;
        });

        await _identificarTipoECarregarPlanos();
        await _atualizarStatusVisualPlanos();

        if (!mounted) {
          return;
        }

        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Plano manual cancelado com sucesso. Você retornou ao plano Grátis.',
            ),
            backgroundColor: Colors.green,
            duration: Duration(seconds: 5),
          ),
        );

        return;
      }

      if (_idPlanoAtivoUsuario == null) {
        throw 'Não foi possível identificar o plano ativo.';
      }

      final String planoAtivoId = _idPlanoAtivoUsuario.toString();

      // Descobre o provedor REAL do plano atual. Não basta existir um
      // registro Google antigo para concluir que o plano ativo é Google.
      // Para recorrentes, consultamos a assinatura Efí e a compra Google.
      // Para avulsos, consultamos o pagamento Efí e a compra Google.
      final compraGoogle = await _buscarCompraGoogleDoPlanoAtivo(
        supabase: supabase,
        usuarioId: user.id,
        planoId: planoAtivoId,
      );

      Map<String, dynamic>? assinaturaEfi;
      Map<String, dynamic>? pagamentoEfi;

      if (_recorrenteAtivo) {
        assinaturaEfi = await _buscarAssinaturaEfiDoPlanoAtivo(
          supabase: supabase,
          usuarioId: user.id,
          planoId: planoAtivoId,
        );
      } else {
        pagamentoEfi = await _buscarPagamentoAvulsoMaisRecente(
          supabase: supabase,
          usuarioId: user.id,
          planoId: planoAtivoId,
        );
      }

      final String provedor = _resolverProvedorPlanoAtivo(
        recorrenteAtual: _recorrenteAtivo,
        assinaturaEfi: assinaturaEfi,
        pagamentoEfi: pagamentoEfi,
        compraGoogle: compraGoogle,
      );

      debugPrint(
        'Provedor identificado para cancelamento: '
        '${provedor.isEmpty ? 'não identificado' : provedor.toUpperCase()} '
        '| plano=$planoAtivoId | recorrente=$_recorrenteAtivo '
        '| efi_subscription=${assinaturaEfi?['efi_subscription_id'] ?? '-'} '
        '| google_product=${compraGoogle?['google_product_id'] ?? '-'}',
      );

      if (provedor.isEmpty) {
        throw _recorrenteAtivo
            ? 'Não foi possível identificar o provedor da assinatura recorrente ativa.'
            : 'Não foi possível identificar o provedor do pagamento deste plano.';
      }

      if (provedor == 'google') {
        final compraGoogleConfirmada = compraGoogle;
        if (compraGoogleConfirmada == null) {
          throw 'O provedor Google foi identificado, mas a compra ativa não foi localizada.';
        }

        cancelamentoGoogle = true;

        final String tipoCompra = compraGoogleConfirmada['tipo_compra']
                ?.toString()
                .trim()
                .toLowerCase() ??
            '';

        final String basePlan =
            compraGoogleConfirmada['google_base_plan_id']?.toString().trim() ??
                '';

        googleRecorrente = compraGoogleConfirmada['recorrente'] == true ||
            tipoCompra == 'recorrente' ||
            basePlan.isNotEmpty;

        final dataGoogle = await _cancelarPlanoGoogleNoBackend(
          accessToken: session.accessToken,
          planoId: planoAtivoId,
          compraGoogle: compraGoogleConfirmada,
        );

        mensagemGoogle = dataGoogle['mensagem']?.toString().trim() ??
            dataGoogle['message']?.toString().trim() ??
            '';

        debugPrint(
          'Cancelamento Google confirmado pelo backend: '
          'plano=$planoAtivoId '
          '| recorrente=$googleRecorrente '
          '| status=${dataGoogle['status'] ?? '-'}',
        );
      } else if (provedor == 'efi' && _recorrenteAtivo) {
        // ======================================================
        // EFÍ - ASSINATURA RECORRENTE
        // ======================================================
        final response = await http
            .post(
              Uri.parse(
                '$_backendUrl/cancelar-assinatura',
              ),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer ${session.accessToken}',
              },
              body: jsonEncode({
                'subscription_id': assinaturaEfi?['efi_subscription_id'],
                'plano_id': planoAtivoId,
                'motivo': 'Cancelamento solicitado pelo usuário no aplicativo.',
              }),
            )
            .timeout(
              const Duration(
                seconds: 45,
              ),
            );

        Map<String, dynamic> data = {};

        try {
          final decoded = jsonDecode(response.body);

          if (decoded is Map) {
            data = Map<String, dynamic>.from(decoded);
          }
        } catch (_) {
          if (response.statusCode < 200 || response.statusCode >= 300) {
            throw 'O servidor retornou uma resposta inválida ao cancelar a assinatura.';
          }
        }

        if (response.statusCode < 200 || response.statusCode >= 300) {
          dynamic mensagemServidor = data['error'] ??
              data['message'] ??
              'Não foi possível cancelar a assinatura.';

          if (mensagemServidor is Map || mensagemServidor is List) {
            mensagemServidor = jsonEncode(mensagemServidor);
          }

          throw mensagemServidor.toString();
        }

        if (data['success'] != true) {
          dynamic mensagemServidor = data['error'] ??
              data['message'] ??
              'A Efí não confirmou o cancelamento da assinatura.';

          if (mensagemServidor is Map || mensagemServidor is List) {
            mensagemServidor = jsonEncode(mensagemServidor);
          }

          throw mensagemServidor.toString();
        }

        final statusCancelamento =
            data['status']?.toString().trim().toLowerCase() ?? '';

        if (statusCancelamento.isNotEmpty &&
            statusCancelamento != 'cancelado' &&
            statusCancelamento != 'canceled' &&
            statusCancelamento != 'cancelled') {
          throw 'A assinatura não retornou status de cancelamento confirmado.';
        }
      } else {
        // ======================================================
        // EFÍ - PLANO AVULSO CARTÃO OU PIX
        // ======================================================
        final pagamento = pagamentoEfi;

        if (pagamento == null) {
          throw 'Não foi encontrado um pagamento elegível para este plano.';
        }

        final pagamentoId = pagamento['id']?.toString().trim() ?? '';

        if (pagamentoId.isEmpty) {
          throw 'O pagamento localizado não possui um identificador válido.';
        }

        final tipoPagamento =
            pagamento['tipo_pagamento']?.toString().trim().toLowerCase() ?? '';

        if (tipoPagamento != 'cartao' && tipoPagamento != 'pix') {
          throw 'O meio de pagamento deste plano não permite cancelamento automático.';
        }

        final statusPagamento =
            pagamento['status']?.toString().trim().toLowerCase() ?? '';

        if (statusPagamento == 'estornado' || statusPagamento == 'refunded') {
          statusCancelamentoAvulso = 'estornado';

          mensagemCancelamentoAvulso = tipoPagamento == 'pix'
              ? 'Este Pix já estava devolvido.'
              : 'Este pagamento já estava estornado.';
        } else {
          final String endpointCancelamento;
          final String motivoCancelamento;

          if (tipoPagamento == 'pix') {
            endpointCancelamento = '$_backendUrl/cancelar-pagamento-pix';
            motivoCancelamento =
                'Cancelamento e devolução Pix solicitados pelo usuário no aplicativo dentro do prazo de 7 dias.';
          } else {
            endpointCancelamento = '$_backendUrl/cancelar-pagamento-cartao';
            motivoCancelamento =
                'Cancelamento solicitado pelo usuário no aplicativo dentro do prazo de 7 dias.';
          }

          final response = await http
              .post(
                Uri.parse(
                  endpointCancelamento,
                ),
                headers: {
                  'Content-Type': 'application/json',
                  'Authorization': 'Bearer ${session.accessToken}',
                },
                body: jsonEncode({
                  'pagamento_id': pagamentoId,
                  'motivo_cancelamento': motivoCancelamento,
                }),
              )
              .timeout(
                const Duration(
                  seconds: 60,
                ),
              );

          Map<String, dynamic> data = {};

          try {
            final decoded = jsonDecode(response.body);

            if (decoded is Map) {
              data = Map<String, dynamic>.from(decoded);
            }
          } catch (_) {
            if (response.statusCode < 200 || response.statusCode >= 300) {
              throw tipoPagamento == 'pix'
                  ? 'O servidor retornou uma resposta inválida ao solicitar a devolução do Pix.'
                  : 'O servidor retornou uma resposta inválida ao solicitar o estorno do cartão.';
            }
          }

          if (response.statusCode < 200 || response.statusCode >= 300) {
            dynamic mensagemServidor = data['error'] ??
                data['message'] ??
                data['mensagem'] ??
                (tipoPagamento == 'pix'
                    ? 'Não foi possível solicitar a devolução do Pix.'
                    : 'Não foi possível solicitar o estorno do pagamento.');

            if (mensagemServidor is Map || mensagemServidor is List) {
              mensagemServidor = jsonEncode(mensagemServidor);
            }

            throw mensagemServidor.toString();
          }

          if (data['success'] != true) {
            dynamic mensagemServidor = data['error'] ??
                data['message'] ??
                data['mensagem'] ??
                (tipoPagamento == 'pix'
                    ? 'O backend não confirmou a solicitação de devolução do Pix.'
                    : 'O backend não confirmou o registro do cancelamento.');

            if (mensagemServidor is Map || mensagemServidor is List) {
              mensagemServidor = jsonEncode(mensagemServidor);
            }

            throw mensagemServidor.toString();
          }

          statusCancelamentoAvulso =
              data['status']?.toString().trim().toLowerCase() ?? '';

          final bool jaEstornado = data['ja_estornado'] == true;
          final bool jaSolicitado = data['ja_solicitado'] == true;
          final bool aguardandoEstorno = data['aguardando_estorno'] == true;

          final bool statusAceito = jaEstornado ||
              jaSolicitado ||
              aguardandoEstorno ||
              statusCancelamentoAvulso == 'estorno_pendente' ||
              statusCancelamentoAvulso == 'estorno_solicitado' ||
              statusCancelamentoAvulso == 'estornado' ||
              statusCancelamentoAvulso == 'refunded';

          if (!statusAceito) {
            throw tipoPagamento == 'pix'
                ? 'O backend respondeu com sucesso, mas não confirmou a devolução do Pix.'
                : 'O backend respondeu com sucesso, mas não confirmou o registro do cancelamento.';
          }

          mensagemCancelamentoAvulso =
              data['mensagem']?.toString().trim() ?? '';

          if (mensagemCancelamentoAvulso.isEmpty) {
            if (tipoPagamento == 'cartao' &&
                (statusCancelamentoAvulso == 'estorno_pendente' ||
                    aguardandoEstorno)) {
              mensagemCancelamentoAvulso =
                  'Cancelamento registrado. O estorno será enviado automaticamente '
                  'assim que a Efí liberar a cobrança para reembolso.';
            } else if (tipoPagamento == 'pix' &&
                statusCancelamentoAvulso == 'estorno_solicitado') {
              mensagemCancelamentoAvulso =
                  'A solicitação de devolução do Pix foi enviada à Efí.';
            } else if (tipoPagamento == 'pix' &&
                (statusCancelamentoAvulso == 'estornado' ||
                    statusCancelamentoAvulso == 'refunded' ||
                    jaEstornado)) {
              mensagemCancelamentoAvulso = 'A devolução do Pix foi concluída.';
            } else {
              mensagemCancelamentoAvulso =
                  'Solicitação de estorno enviada à Efí.';
            }
          }
        }
      }

      // Só retorna ao plano Grátis depois que o provedor correto
      // confirmou o cancelamento/registro do cancelamento.
      final responseGratis = await _buscarPlanoGratisDoMesmoTipo(
        supabase: supabase,
      );

      String nomeCompletoGratis =
          responseGratis['nome_plano']?.toString().trim() ?? 'Grátis';

      String nomeBaseGratis = nomeCompletoGratis;

      if (nomeCompletoGratis.contains('-')) {
        nomeBaseGratis = nomeCompletoGratis.split('-').last.trim();
      }

      try {
        await supabase.from('tab_usuarios').update({
          'nome_plano_ativo': nomeBaseGratis,
          'id_plano_atual': responseGratis['id'],
          'plano_id': responseGratis['id'],
          'recorrente': false,
          'plano_data_ativacao': null,
        }).eq(
          'id',
          user.id,
        );
      } catch (_) {
        await supabase.from('tab_usuarios').update({
          'nome_plano_ativo': nomeBaseGratis,
          'id_plano_atual': responseGratis['id'],
          'plano_id': responseGratis['id'],
          'plano_data_ativacao': null,
        }).eq(
          'id',
          user.id,
        );
      }

      if (mounted && dialogCarregamentoAberto) {
        Navigator.of(
          context,
          rootNavigator: true,
        ).pop();

        dialogCarregamentoAberto = false;
      }

      if (!mounted) {
        return;
      }

      setState(() {
        _planoAtivoUsuario = nomeBaseGratis.toLowerCase();
        _idPlanoAtivoUsuario = responseGratis['id'];
        _recorrenteAtivo = false;
        _planoDataAtivacao = null;
        _statusAssinatura = eraRecorrente ? 'cancelado' : '';
        _dataFimCarencia = null;
      });

      await _identificarTipoECarregarPlanos();
      await _atualizarStatusVisualPlanos();

      if (!mounted) {
        return;
      }

      String mensagemFinal;
      Color corMensagem = Colors.green;

      if (cancelamentoGoogle) {
        if (mensagemGoogle.isNotEmpty) {
          mensagemFinal = mensagemGoogle;
        } else if (googleRecorrente) {
          mensagemFinal =
              'Renovação da assinatura Google Play cancelada com sucesso. '
              'Você retornou ao plano Grátis.';
        } else {
          mensagemFinal = 'Cancelamento da compra Google Play confirmado. '
              'Você retornou ao plano Grátis.';
        }
      } else if (eraRecorrente) {
        mensagemFinal = 'Assinatura recorrente cancelada na Efí com sucesso! '
            'Você retornou ao plano Grátis.';
      } else if (statusCancelamentoAvulso == 'estorno_pendente') {
        mensagemFinal = mensagemCancelamentoAvulso.isNotEmpty
            ? '$mensagemCancelamentoAvulso Você retornou ao plano Grátis.'
            : 'Cancelamento registrado. O estorno está pendente. '
                'Você retornou ao plano Grátis.';
        corMensagem = Colors.orange;
      } else {
        mensagemFinal = mensagemCancelamentoAvulso.isNotEmpty
            ? '$mensagemCancelamentoAvulso Você retornou ao plano Grátis.'
            : 'Plano cancelado com sucesso. Você retornou ao plano Grátis.';
      }

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            mensagemFinal,
          ),
          backgroundColor: corMensagem,
          duration: const Duration(
            seconds: 7,
          ),
        ),
      );
    } catch (e) {
      if (mounted && dialogCarregamentoAberto) {
        Navigator.of(
          context,
          rootNavigator: true,
        ).pop();

        dialogCarregamentoAberto = false;
      }

      if (mounted) {
        final mensagem = e.toString().replaceFirst('Exception: ', '').trim();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              mensagem.isEmpty
                  ? 'Não foi possível cancelar o plano.'
                  : mensagem,
            ),
            backgroundColor: Colors.redAccent,
            duration: const Duration(
              seconds: 7,
            ),
          ),
        );
      }
    }
  }

  String _formatarValorPagamento(double valor) {
    return valor.toStringAsFixed(2).replaceAll('.', ',');
  }

  bool _googleDisponivelNoPlano(Map<String, dynamic> plano) {
    return _toBool(plano['google_ativo']);
  }

  Future<String?> _buscarPrecoGoogleDoPlano(
    Map<String, dynamic> plano, {
    required bool isRecorrente,
  }) async {
    final String productId = _googleProductIdDoPlano(
      plano,
      isRecorrente: isRecorrente,
    );

    if (productId.isEmpty) return null;

    try {
      final resposta = await InAppPurchase.instance.queryProductDetails(
        <String>{productId},
      );

      if (resposta.error != null || resposta.productDetails.isEmpty) {
        return null;
      }

      final String basePlanId = _googleBasePlanIdDoPlano(plano);

      if (isRecorrente && basePlanId.isNotEmpty) {
        for (final produto in resposta.productDetails) {
          if (produto.id != productId || produto is! GooglePlayProductDetails) {
            continue;
          }

          final ofertas =
              produto.productDetails.subscriptionOfferDetails ?? const [];
          final index = produto.subscriptionIndex;

          if (index != null &&
              index >= 0 &&
              index < ofertas.length &&
              ofertas[index].basePlanId == basePlanId) {
            return produto.price;
          }

          final candidatos = GooglePlayProductDetails.fromProductDetails(
            produto.productDetails,
          );

          for (final candidato in candidatos) {
            final idx = candidato.subscriptionIndex;
            if (idx != null &&
                idx >= 0 &&
                idx < ofertas.length &&
                ofertas[idx].basePlanId == basePlanId) {
              return candidato.price;
            }
          }
        }
      }

      for (final produto in resposta.productDetails) {
        if (produto.id == productId) return produto.price;
      }

      return resposta.productDetails.first.price;
    } catch (e) {
      debugPrint('Não foi possível consultar o preço Google Play: $e');
      return null;
    }
  }

  String _googleProductIdDoPlano(
    Map<String, dynamic> plano, {
    required bool isRecorrente,
  }) {
    // No Google Play usamos produtos diferentes para cada modalidade:
    // - recorrente: google_product_id (assinatura)
    // - avulso: google_product_id_avulso (produto único/consumível)
    final dynamic valor = isRecorrente
        ? plano['google_product_id']
        : plano['google_product_id_avulso'];

    return valor?.toString().trim() ?? '';
  }

  String _googleBasePlanIdDoPlano(
    Map<String, dynamic> plano,
  ) {
    return plano['google_base_plan_id']?.toString().trim() ?? '';
  }

  Future<bool> _abrirCheckoutEfi({
    required Map<String, dynamic> plano,
    required bool isRecorrente,
    String? metodoPagamentoFixo,
  }) async {
    // Proteção adicional: mesmo que outra ação chame este método,
    // o checkout EfíPay não abre nesta distribuição de planos digitais.
    if (_somenteGooglePlay) {
      debugPrint(
          'Checkout EfíPay bloqueado para planos digitais nesta distribuição.');
      return false;
    }

    final String efiPlanId = plano['efi_plan_id']?.toString().trim() ?? '';

    if (isRecorrente && efiPlanId.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Este plano ainda precisa ser vinculado ao plano correspondente na Efí.',
            ),
            backgroundColor: Colors.orange,
          ),
        );
      }

      return false;
    }

    final resultado = await showDialog<dynamic>(
      context: context,
      builder: (context) => CheckoutModal(
        origemTipo: 'plano_categoria',
        origemId: plano['id'].toString(),
        ehRecorrente: isRecorrente,
        metodoPagamentoFixo: metodoPagamentoFixo,
      ),
    );

    return resultado == true;
  }

  Future<bool> _abrirCheckoutGoogle({
    required Map<String, dynamic> plano,
    required bool isRecorrente,
  }) async {
    final bool googleAtivo = _googleDisponivelNoPlano(
      plano,
    );

    final String googleProductId = _googleProductIdDoPlano(
      plano,
      isRecorrente: isRecorrente,
    );

    // Base Plan existe somente para assinatura recorrente.
    // Em compra avulsa, mesmo que o plano possua google_base_plan_id no
    // Supabase por causa da modalidade recorrente, NÃO devemos enviá-lo
    // ao CheckoutGooglePage. Caso contrário o checkout classifica o
    // produto *_avulso como assinatura recorrente.
    final String googleBasePlanId = isRecorrente
        ? _googleBasePlanIdDoPlano(
            plano,
          )
        : '';

    if (!googleAtivo) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'O pagamento pela Google Play ainda não está ativo para este plano.',
            ),
            backgroundColor: Colors.orange,
          ),
        );
      }

      return false;
    }

    // Compra avulsa não possui base plan. O base plan é obrigatório
    // somente para assinaturas recorrentes.
    if (googleProductId.isEmpty || (isRecorrente && googleBasePlanId.isEmpty)) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Este plano ainda precisa ser configurado na Google Play.',
            ),
            backgroundColor: Colors.orange,
          ),
        );
      }

      return false;
    }

    final String nomeCompleto =
        plano['nome_plano']?.toString().trim() ?? 'Plano';

    final bool? resultado = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (pageContext) {
          return CheckoutGooglePage(
            planoId: plano['id'].toString(),
            nomePlano: nomeCompleto,
            googleProductId: googleProductId,
            googleBasePlanId: googleBasePlanId,
            serverGoogleUrl: _googleBackendUrl,
            onCompraAprovada: () {
              if (Navigator.of(pageContext).canPop()) {
                Navigator.of(pageContext).pop(
                  true,
                );
              }
            },
          );
        },
      ),
    );

    return resultado == true;
  }

  Widget _buildOpcaoPagamento({
    required IconData icone,
    required String titulo,
    required String subtitulo,
    required String preco,
    required VoidCallback? onTap,
    bool destaque = false,
    bool indisponivel = false,
  }) {
    final Color corBorda = destaque
        ? const Color(
            0xFFFF8C00,
          )
        : Colors.white24;

    return Material(
      color: Colors.transparent,
      child: InkWell(
        onTap: indisponivel ? null : onTap,
        borderRadius: BorderRadius.circular(
          14,
        ),
        child: Container(
          width: double.infinity,
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 14,
          ),
          decoration: BoxDecoration(
            color: indisponivel
                ? Colors.white.withValues(
                    alpha: 0.03,
                  )
                : const Color(
                    0xFF1A2C42,
                  ),
            borderRadius: BorderRadius.circular(
              14,
            ),
            border: Border.all(
              color: indisponivel ? Colors.white12 : corBorda,
              width: destaque ? 1.5 : 1,
            ),
          ),
          child: Row(
            children: [
              Container(
                width: 44,
                height: 44,
                decoration: BoxDecoration(
                  color: const Color(
                    0xFFFF8C00,
                  ).withValues(
                    alpha: indisponivel ? 0.08 : 0.13,
                  ),
                  borderRadius: BorderRadius.circular(
                    12,
                  ),
                ),
                child: Icon(
                  icone,
                  color: indisponivel
                      ? Colors.white30
                      : const Color(
                          0xFFFF8C00,
                        ),
                ),
              ),
              const SizedBox(
                width: 12,
              ),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      titulo,
                      style: TextStyle(
                        color: indisponivel ? Colors.white38 : Colors.white,
                        fontSize: 15,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(
                      height: 3,
                    ),
                    Text(
                      subtitulo,
                      style: TextStyle(
                        color: indisponivel ? Colors.white24 : Colors.white60,
                        fontSize: 11,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(
                width: 10,
              ),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  Text(
                    preco,
                    style: TextStyle(
                      color: indisponivel
                          ? Colors.white30
                          : const Color(
                              0xFFFF8C00,
                            ),
                      fontSize: 15,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                  if (indisponivel) ...[
                    const SizedBox(
                      height: 3,
                    ),
                    const Text(
                      'EM BREVE',
                      style: TextStyle(
                        color: Colors.white30,
                        fontSize: 9,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 0.7,
                      ),
                    ),
                  ],
                ],
              ),
              const SizedBox(
                width: 8,
              ),
              Icon(
                Icons.chevron_right,
                color: indisponivel ? Colors.white24 : Colors.white54,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Future<String?> _escolherFormaPagamentoAvulso(
    Map<String, dynamic> plano,
  ) async {
    final double valorEfi = _toDouble(
      plano['valor'],
    );

    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.all(
              14,
            ),
            padding: const EdgeInsets.fromLTRB(
              18,
              18,
              18,
              20,
            ),
            decoration: BoxDecoration(
              color: const Color(
                0xFF101B2B,
              ),
              borderRadius: BorderRadius.circular(
                20,
              ),
              border: Border.all(
                color: Colors.white12,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    const Expanded(
                      child: Text(
                        'Como deseja pagar?',
                        style: TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(
                        context,
                      ),
                      icon: const Icon(
                        Icons.close,
                        color: Colors.white54,
                      ),
                    ),
                  ],
                ),
                const Text(
                  'Escolha a forma de pagamento. O processo é rápido e seguro.',
                  style: TextStyle(
                    color: Colors.white60,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(
                  height: 18,
                ),
                _buildOpcaoPagamento(
                  icone: Icons.pix,
                  titulo: 'PIX',
                  subtitulo: 'Pagamento avulso pela EfíPay',
                  preco: 'R\$ ${_formatarValorPagamento(valorEfi)}',
                  destaque: true,
                  onTap: () => Navigator.pop(
                    context,
                    'pix',
                  ),
                ),
                const SizedBox(
                  height: 12,
                ),
                _buildOpcaoPagamento(
                  icone: Icons.credit_card,
                  titulo: 'Cartão',
                  subtitulo: 'Escolha EfíPay ou Google Play',
                  preco: 'a partir de R\$ ${_formatarValorPagamento(valorEfi)}',
                  onTap: () => Navigator.pop(
                    context,
                    'cartao',
                  ),
                ),
              ],
            ),
          ),
        );
      },
    );
  }

  Future<String?> _escolherGatewayCartao({
    required Map<String, dynamic> plano,
    required bool isRecorrente,
  }) async {
    final double valorEfi = isRecorrente
        ? _toDouble(
            plano['valor_recorrente'],
          )
        : _toDouble(
            plano['valor'],
          );

    // Consulta o preço localizado diretamente no Google Play antes de
    // abrir a janela de escolha. Assim o valor exibido ao lado de
    // "Google Play" é exatamente o mesmo que aparecerá no checkout.
    final String? precoGoogle = await _buscarPrecoGoogleDoPlano(
      plano,
      isRecorrente: isRecorrente,
    );

    final String googleProductId = _googleProductIdDoPlano(
      plano,
      isRecorrente: isRecorrente,
    );

    final String googleBasePlanId = _googleBasePlanIdDoPlano(
      plano,
    );

    // O preço não é condição para liberar o Google Play.
    // A disponibilidade depende apenas da configuração do produto:
    // - avulso: google_ativo + google_product_id_avulso
    // - recorrente: google_ativo + google_product_id + google_base_plan_id
    // O preço definitivo/localizado é obtido pela própria Google Play
    // durante o fluxo de compra.
    final bool googleAtivo = _googleDisponivelNoPlano(
          plano,
        ) &&
        googleProductId.isNotEmpty &&
        (!isRecorrente || googleBasePlanId.isNotEmpty);

    // Houve uma operação assíncrona ao consultar o preço do Google Play.
    // A tela pode ter sido fechada nesse intervalo; nesse caso, não abra
    // um modal usando um BuildContext que já não está montado.
    if (!mounted) return null;

    return showModalBottomSheet<String>(
      context: context,
      backgroundColor: Colors.transparent,
      isScrollControlled: true,
      builder: (context) {
        return SafeArea(
          child: Container(
            margin: const EdgeInsets.all(
              14,
            ),
            padding: const EdgeInsets.fromLTRB(
              18,
              18,
              18,
              20,
            ),
            decoration: BoxDecoration(
              color: const Color(
                0xFF101B2B,
              ),
              borderRadius: BorderRadius.circular(
                20,
              ),
              border: Border.all(
                color: Colors.white12,
              ),
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    Expanded(
                      child: Text(
                        isRecorrente
                            ? 'Escolha a assinatura'
                            : 'Pague com cartão',
                        style: const TextStyle(
                          color: Colors.white,
                          fontSize: 20,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                    IconButton(
                      onPressed: () => Navigator.pop(
                        context,
                      ),
                      icon: const Icon(
                        Icons.close,
                        color: Colors.white54,
                      ),
                    ),
                  ],
                ),
                Text(
                  isRecorrente
                      ? 'Escolha por onde deseja fazer a cobrança mensal.'
                      : 'Escolha por onde deseja concluir o pagamento.',
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 12,
                  ),
                ),
                const SizedBox(
                  height: 18,
                ),
                _buildOpcaoPagamento(
                  icone: Icons.account_balance_wallet_outlined,
                  titulo: 'EfíPay',
                  subtitulo: isRecorrente
                      ? 'Assinatura mensal pela EfíPay'
                      : 'Pagamento por cartão pela EfíPay',
                  preco: 'R\$ ${_formatarValorPagamento(valorEfi)}',
                  destaque: true,
                  onTap: () => Navigator.pop(
                    context,
                    'efi',
                  ),
                ),
                const SizedBox(
                  height: 12,
                ),
                _buildOpcaoPagamento(
                  icone: Icons.play_circle_outline,
                  titulo: 'Google Play',
                  subtitulo: isRecorrente
                      ? 'Assinatura pela Google Play'
                      : 'Pagamento pela Google Play',
                  preco: precoGoogle != null && precoGoogle.trim().isNotEmpty
                      ? precoGoogle
                      : (googleAtivo ? 'Ver preço' : 'A configurar'),
                  indisponivel: !googleAtivo,
                  onTap: () => Navigator.pop(
                    context,
                    'google',
                  ),
                ),
                if (!googleAtivo) ...[
                  const SizedBox(
                    height: 10,
                  ),
                  const Text(
                    'Google Play ficará disponível assim que este plano estiver ativado no Play Console e no Supabase.',
                    style: TextStyle(
                      color: Colors.white38,
                      fontSize: 10,
                      height: 1.3,
                    ),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Future<bool> _processarPagamentoPlano({
    required Map<String, dynamic> plano,
    required bool isRecorrente,
  }) async {
    // Play Store: compra avulsa e assinatura recorrente seguem diretamente
    // para o checkout Google, sem oferecer Pix ou cartão pela EfíPay.
    if (_somenteGooglePlay) {
      return _abrirCheckoutGoogle(
        plano: plano,
        isRecorrente: isRecorrente,
      );
    }

    // =========================================================
    // RECORRENTE
    // Abre direto EfíPay x Google Play.
    // =========================================================

    if (isRecorrente) {
      final gateway = await _escolherGatewayCartao(
        plano: plano,
        isRecorrente: true,
      );

      if (gateway == null) {
        return false;
      }

      if (gateway == 'efi') {
        return _abrirCheckoutEfi(
          plano: plano,
          isRecorrente: true,
          metodoPagamentoFixo: 'cartao',
        );
      }

      if (gateway == 'google') {
        return _abrirCheckoutGoogle(
          plano: plano,
          isRecorrente: true,
        );
      }

      return false;
    }

    // =========================================================
    // AVULSO
    // PIX -> EfíPay direto.
    // CARTÃO -> EfíPay x Google Play.
    // =========================================================

    final forma = await _escolherFormaPagamentoAvulso(
      plano,
    );

    if (forma == null) {
      return false;
    }

    if (forma == 'pix') {
      // O CheckoutModal atual da Efí já abre o pagamento avulso
      // com PIX selecionado por padrão.
      return _abrirCheckoutEfi(
        plano: plano,
        isRecorrente: false,
        metodoPagamentoFixo: 'pix',
      );
    }

    if (forma == 'cartao') {
      final gateway = await _escolherGatewayCartao(
        plano: plano,
        isRecorrente: false,
      );

      if (gateway == null) {
        return false;
      }

      if (gateway == 'efi') {
        // Abre diretamente o formulário de cartão da Efí,
        // sem exibir a opção PIX novamente.
        return _abrirCheckoutEfi(
          plano: plano,
          isRecorrente: false,
          metodoPagamentoFixo: 'cartao',
        );
      }

      if (gateway == 'google') {
        return _abrirCheckoutGoogle(
          plano: plano,
          isRecorrente: false,
        );
      }
    }

    return false;
  }

  Future<void> _ativarPlanoAposPagamento({
    required User user,
    required Map<String, dynamic> plano,
    required bool isRecorrente,
    required String agoraIso,
  }) async {
    String nomeCompleto = plano['nome_plano']?.toString() ?? '';

    String nomeBase = nomeCompleto;

    if (nomeCompleto.contains('-')) {
      nomeBase = nomeCompleto.split('-').last.trim();
    }

    final supabase = Supabase.instance.client;

    try {
      // ----------------------------------------------------------
      // ATUALIZA O PLANO DO USUÁRIO SOMENTE APÓS O PAGAMENTO
      // TER SIDO CONFIRMADO PELO CHECKOUT.
      // ----------------------------------------------------------

      try {
        await supabase.from('tab_usuarios').update({
          'nome_plano_ativo': nomeBase,
          'id_plano_atual': plano['id'],
          'plano_id': plano['id'],
          'recorrente': isRecorrente,
          'plano_data_ativacao': agoraIso,
        }).eq(
          'id',
          user.id,
        );
      } catch (_) {
        // Compatibilidade com base antiga sem coluna recorrente.
        await supabase.from('tab_usuarios').update({
          'nome_plano_ativo': nomeBase,
          'id_plano_atual': plano['id'],
          'plano_id': plano['id'],
          'plano_data_ativacao': agoraIso,
        }).eq(
          'id',
          user.id,
        );
      }

      // ----------------------------------------------------------
      // CONFIRMA NO BANCO QUE O NOVO PLANO FOI REALMENTE GRAVADO.
      // ----------------------------------------------------------
      //
      // Isso evita mostrar "plano ativado" no celular quando, por
      // qualquer motivo, a atualização do Supabase não persistiu.
      // ----------------------------------------------------------

      final usuarioAtualizado = await supabase
          .from('tab_usuarios')
          .select(
            'nome_plano_ativo, id_plano_atual, plano_id, recorrente, plano_data_ativacao',
          )
          .eq(
            'id',
            user.id,
          )
          .maybeSingle();

      if (usuarioAtualizado == null) {
        throw 'O pagamento foi confirmado, mas não foi possível confirmar a atualização do plano no banco.';
      }

      final idGravado =
          usuarioAtualizado['id_plano_atual'] ?? usuarioAtualizado['plano_id'];

      if (idGravado == null ||
          idGravado.toString().trim() != plano['id'].toString().trim()) {
        throw 'O pagamento foi confirmado, mas o novo plano ainda não foi gravado corretamente no usuário.';
      }

      // Atualiza imediatamente o estado local antes de recarregar toda a tela.
      if (mounted) {
        setState(() {
          _planoAtivoUsuario = nomeBase.toLowerCase();
          _idPlanoAtivoUsuario = plano['id'];
          _recorrenteAtivo = isRecorrente;
          _planoDataAtivacao = _parseDataSupabaseUtc(
            agoraIso,
          );

          // Ao entrar em um plano avulso, não reaproveita status de
          // assinatura recorrente anterior na interface.
          if (!isRecorrente) {
            _statusAssinatura = '';
            _efiSubscriptionId = null;
            _dataFimCarencia = null;
          }
        });
      }

      await _identificarTipoECarregarPlanos();

      if (mounted) {
        await _mostrarDialogPagamentoConfirmado(
          nomePlano: nomeBase,
        );
      }
    } catch (e) {
      debugPrint(
        'Erro ao ativar plano após pagamento confirmado: $e',
      );

      rethrow;
    }
  }

  Future<void> _carregarProdutosApple() async {
    if (!Platform.isIOS || _carregandoProdutosApple) return;
    _carregandoProdutosApple = true;
    _erroProdutosApple = null;
    if (mounted) setState(() {});
    try {
      _appleDisponivel = await _iapApple.isAvailable();
      if (!_appleDisponivel) {
        _erroProdutosApple =
            'A App Store não está disponível neste dispositivo.';
        return;
      }
      final ids = <String>{};
      for (final plano in _planosDisponiveis) {
        if (!_toBool(plano['apple_ativo'])) continue;
        final recorrente = (plano['apple_product_id'] ?? '').toString().trim();
        final avulso =
            (plano['apple_product_id_avulso'] ?? '').toString().trim();
        if (recorrente.isNotEmpty) ids.add(recorrente);
        if (avulso.isNotEmpty) ids.add(avulso);
      }
      if (ids.isEmpty) {
        _erroProdutosApple =
            'Os produtos Apple ainda não foram configurados para estes planos.';
        return;
      }
      final resposta = await _iapApple.queryProductDetails(ids);
      _produtosApple
        ..clear()
        ..addEntries(resposta.productDetails.map((p) => MapEntry(p.id, p)));
      if (resposta.error != null) {
        _erroProdutosApple =
            'Erro ao consultar preços da App Store: ${resposta.error!.message}';
      } else if (resposta.notFoundIDs.isNotEmpty) {
        _erroProdutosApple =
            'Alguns produtos não foram encontrados na App Store. Confira os IDs.';
      }
    } catch (e) {
      _erroProdutosApple = 'Erro ao consultar produtos Apple: $e';
      debugPrint('Erro ao consultar produtos StoreKit: $e');
    } finally {
      _carregandoProdutosApple = false;
      if (mounted) setState(() {});
    }
  }

  ProductDetails? _produtoAppleDoPlano(
    Map<String, dynamic> plano, {
    required bool recorrente,
  }) {
    if (!Platform.isIOS) return null;
    final campo = recorrente ? 'apple_product_id' : 'apple_product_id_avulso';
    final id = plano[campo]?.toString().trim() ?? '';
    if (id.isEmpty) return null;
    return _produtosApple[id];
  }

  Future<bool> _abrirCheckoutApple({
    required Map<String, dynamic> plano,
    required bool isRecorrente,
  }) async {
    final bool appleAtivo = _toBool(plano['apple_ativo']);
    final String campoProduto =
        isRecorrente ? 'apple_product_id' : 'apple_product_id_avulso';
    final String appleProductId = plano[campoProduto]?.toString().trim() ?? '';

    if (!appleAtivo) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'O pagamento pela App Store ainda não está ativo para este plano.',
            ),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return false;
    }

    if (appleProductId.isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              isRecorrente
                  ? 'Configure apple_product_id para a assinatura deste plano.'
                  : 'Configure apple_product_id_avulso para a compra avulsa deste plano.',
            ),
            backgroundColor: Colors.orange,
          ),
        );
      }
      return false;
    }

    if (_appleBackendUrl.trim().isEmpty) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'O backend Apple ainda não foi configurado. '
              'Defina ACHE_OBRA_APPLE_BACKEND_URL antes de habilitar compras.',
            ),
            backgroundColor: Colors.orange,
            duration: Duration(seconds: 7),
          ),
        );
      }
      return false;
    }

    final String nomeCompleto =
        plano['nome_plano']?.toString().trim() ?? 'Plano';

    final bool? resultado = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (pageContext) {
          return CheckoutApplePage(
            planoId: plano['id'].toString(),
            nomePlano: nomeCompleto,
            appleProductId: appleProductId,
            serverAppleUrl: _appleBackendUrl,
            recorrente: isRecorrente,
            onCompraAprovada: () {
              if (Navigator.of(pageContext).canPop()) {
                Navigator.of(pageContext).pop(true);
              }
            },
          );
        },
      ),
    );

    return resultado == true;
  }

  Future<void> _avisarIntegracaoApplePendente() async {
    if (!mounted) return;
    final mensagem = _erroProdutosApple ??
        'A compra Apple depende da validação segura no backend. Nenhum pagamento foi iniciado.';
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(SnackBar(
        content: Text(mensagem),
        backgroundColor: const Color(0xFFFF8C00),
        duration: const Duration(seconds: 6),
      ));
  }

  Future<void> _selecionarPlano(
    Map<String, dynamic> plano,
  ) async {
    // Impede uma nova troca nos primeiros 60 segundos após a
    // ativação do plano atual. A mensagem informa o tempo restante.
    if (_bloquearTrocaPlanoSeNecessario(plano)) {
      return;
    }

    // Evita dois toques seguidos abrirem dois checkouts/cobranças.
    if (_processandoSelecaoPlano) {
      debugPrint(
        'Seleção de plano ignorada: já existe um processo de pagamento em andamento.',
      );
      return;
    }

    final user = Supabase.instance.client.auth.currentUser;

    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text(
            'Você precisa estar logado para assinar um plano.',
          ),
          backgroundColor: Colors.redAccent,
        ),
      );

      return;
    }

    _processandoSelecaoPlano = true;

    try {
      final bool isRecorrente = _escolhaRecorrente[plano['id']] ?? false;

      final double valorAvulso = _toDouble(
        plano['valor'],
      );

      final double valorRecorrente = _toDouble(
        plano['valor_recorrente'],
      );

      final double valorFinal = isRecorrente ? valorRecorrente : valorAvulso;

      // =========================================================
      // PLANOS PAGOS
      // =========================================================
      //
      // O plano atual NÃO é alterado enquanto o checkout não
      // retornar pagamento aprovado.
      //
      // No PIX, isso significa:
      // gerar PIX -> aguardar confirmação real -> CheckoutModal
      // retorna true -> somente então atualizamos tab_usuarios.
      // =========================================================

      if (valorFinal > 0) {
        // Cada plataforma utiliza exclusivamente o seu próprio checkout.
        // No iOS, a tela Apple só retorna sucesso depois da confirmação do
        // backend; no Android, o fluxo Google/Efí existente permanece intacto.
        final bool pagamentoAprovado;
        if (Platform.isIOS) {
          pagamentoAprovado = await _abrirCheckoutApple(
            plano: plano,
            isRecorrente: isRecorrente,
          );
        } else {
          pagamentoAprovado = await _processarPagamentoPlano(
            plano: plano,
            isRecorrente: isRecorrente,
          );
        }

        if (!pagamentoAprovado) {
          debugPrint(
            'Checkout encerrado sem pagamento aprovado. '
            'O plano atual do usuário será mantido.',
          );

          // Em assinatura recorrente, "false" aqui não significa
          // necessariamente que nada foi criado. A Efí pode ter
          // criado a assinatura/cobrança e devolvido status waiting,
          // enquanto o backend grava pagamento_pendente no Supabase.
          //
          // Fazemos várias leituras por alguns segundos para evitar
          // perder esse estado por diferença de tempo entre o retorno
          // do checkout e a persistência/visibilidade no banco.
          if (isRecorrente && !_somenteGooglePlay) {
            final encontrouProcessando =
                await _confirmarPlanoProcessandoAposCheckout(
              planoId: plano['id'],
            );

            if (!encontrouProcessando) {
              // Uma última atualização normal mantém a tela coerente
              // caso o usuário apenas tenha fechado o checkout.
              await _atualizarStatusVisualPlanos();
            }
          }

          return;
        }

        // No iOS, o backend Apple já validou a transação e é a autoridade
        // para gravar o plano no Supabase. Não sobrescrevemos essa gravação
        // pelo aplicativo; apenas recarregamos o estado vindo do banco.
        if (Platform.isIOS) {
          await _identificarTipoECarregarPlanos();

          if (mounted) {
            final nomeCompleto =
                plano['nome_plano']?.toString().trim() ?? 'Plano';
            final nomeBase = nomeCompleto.contains('-')
                ? nomeCompleto.split('-').last.trim()
                : nomeCompleto;

            await _mostrarDialogPagamentoConfirmado(
              nomePlano: nomeBase.isEmpty ? 'Plano' : nomeBase,
            );
          }
          return;
        }

        // Android e demais fluxos preservam a ativação existente após
        // confirmação do respectivo checkout.
        final String agoraIso = DateTime.now().toUtc().toIso8601String();

        _planoDataAtivacao = _parseDataSupabaseUtc(agoraIso);
        _sincronizarTimerTrocaPlano();

        try {
          await _ativarPlanoAposPagamento(
            user: user,
            plano: plano,
            isRecorrente: isRecorrente,
            agoraIso: agoraIso,
          );
        } catch (e) {
          if (!mounted) {
            return;
          }

          final mensagem = e
              .toString()
              .replaceFirst(
                'Exception: ',
                '',
              )
              .trim();

          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                mensagem.isEmpty
                    ? 'O pagamento foi confirmado, mas não foi possível atualizar o plano. Não faça um novo pagamento.'
                    : '$mensagem Não faça um novo pagamento.',
              ),
              backgroundColor: Colors.redAccent,
              duration: const Duration(
                seconds: 8,
              ),
            ),
          );
        }

        return;
      }

      // =========================================================
      // PLANO GRÁTIS
      // =========================================================

      final String agoraIso = DateTime.now().toUtc().toIso8601String();

      _planoDataAtivacao = _parseDataSupabaseUtc(agoraIso);
      _sincronizarTimerTrocaPlano();

      showDialog(
        context: context,
        barrierDismissible: false,
        builder: (context) => const Center(
          child: CircularProgressIndicator(
            color: Color(
              0xFFFF8C00,
            ),
          ),
        ),
      );

      bool dialogAberto = true;

      try {
        String nomeCompleto = plano['nome_plano']?.toString() ?? '';

        String nomeBase = nomeCompleto;

        if (nomeCompleto.contains('-')) {
          nomeBase = nomeCompleto.split('-').last.trim();
        }

        try {
          await Supabase.instance.client.from('tab_usuarios').update({
            'nome_plano_ativo': nomeBase,
            'id_plano_atual': plano['id'],
            'plano_id': plano['id'],
            'recorrente': false,
            'plano_data_ativacao': agoraIso,
          }).eq(
            'id',
            user.id,
          );
        } catch (_) {
          await Supabase.instance.client.from('tab_usuarios').update({
            'nome_plano_ativo': nomeBase,
            'id_plano_atual': plano['id'],
            'plano_id': plano['id'],
            'plano_data_ativacao': agoraIso,
          }).eq(
            'id',
            user.id,
          );
        }

        await _identificarTipoECarregarPlanos();

        if (mounted && dialogAberto) {
          Navigator.pop(
            context,
          );
          dialogAberto = false;
        }

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Parabéns! Plano $nomeBase ativado com sucesso!',
              ),
              backgroundColor: Colors.green,
              duration: const Duration(
                seconds: 3,
              ),
            ),
          );
        }
      } catch (e) {
        _planoDataAtivacao = null;
        _sincronizarTimerTrocaPlano();

        if (mounted && dialogAberto) {
          Navigator.pop(
            context,
          );
          dialogAberto = false;
        }

        debugPrint(
          'Erro ao atualizar plano do usuário: $e',
        );

        if (mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'Não foi possível atualizar o plano: '
                '${e.toString().replaceFirst('Exception: ', '')}',
              ),
              backgroundColor: Colors.redAccent,
              duration: const Duration(
                seconds: 7,
              ),
            ),
          );
        }
      }
    } finally {
      _processandoSelecaoPlano = false;
    }
  }

  @override
  Widget build(
    BuildContext context,
  ) {
    bool usuarioTemPlanoPago = _temPlanoManualAtivo;

    if (!usuarioTemPlanoPago && _idPlanoAtivoUsuario != null) {
      usuarioTemPlanoPago = !_planoAtivoUsuario.contains(
        'gratis',
      );
    }

    final bool exibirBotaoCancelar = _podeExibirBotaoCancelar(
      usuarioTemPlanoPago,
    );

    return Scaffold(
      backgroundColor: const Color(
        0xFF1A2C42,
      ),
      appBar: AppBar(
        backgroundColor: const Color(
          0xFF101B2B,
        ),
        title: Text(
          'Planos: $_tipoRealUsuario',
          style: const TextStyle(
            color: Colors.white,
            fontSize: 18,
            fontWeight: FontWeight.bold,
          ),
        ),
        iconTheme: const IconThemeData(
          color: Colors.white,
        ),
      ),
      body: _carregando
          ? const Center(
              child: CircularProgressIndicator(
                color: Color(
                  0xFFFF8C00,
                ),
              ),
            )
          : Column(
              children: [
                if (_temPlanoManualAtivo)
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      16,
                      16,
                      16,
                      0,
                    ),
                    child: _buildAvisoPlanoManualAtivo(),
                  ),
                if (_recorrenteAtivo &&
                    (_pagamentoPendente ||
                        _assinaturaInadimplente ||
                        _assinaturaCancelada))
                  Padding(
                    padding: const EdgeInsets.fromLTRB(
                      16,
                      16,
                      16,
                      0,
                    ),
                    child: _buildAvisoStatusAssinatura(),
                  ),
                if (usuarioTemPlanoPago)
                  Padding(
                    padding: const EdgeInsets.all(
                      16,
                    ),
                    child: Column(
                      children: [
                        if (exibirBotaoCancelar)
                          SizedBox(
                            width: double.infinity,
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                side: const BorderSide(
                                  color: Colors.redAccent,
                                ),
                                padding: const EdgeInsets.symmetric(
                                  vertical: 12,
                                ),
                                backgroundColor: Colors.red.withValues(
                                  alpha: 0.1,
                                ),
                              ),
                              icon: const Icon(
                                Icons.cancel_outlined,
                                color: Colors.redAccent,
                              ),
                              onPressed: _cancelarPlanoAssinatura,
                              label: const Text(
                                'CANCELAR PLANO',
                                style: TextStyle(
                                  color: Colors.redAccent,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          )
                        else if (!_recorrenteAtivo)
                          Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(
                              12,
                            ),
                            decoration: BoxDecoration(
                              color: const Color(
                                0xFF101B2B,
                              ),
                              borderRadius: BorderRadius.circular(
                                8,
                              ),
                              border: Border.all(
                                color: Colors.white24,
                              ),
                            ),
                            child: const Row(
                              children: [
                                Icon(
                                  Icons.info_outline,
                                  color: Colors.amber,
                                  size: 20,
                                ),
                                SizedBox(
                                  width: 10,
                                ),
                                Expanded(
                                  child: Text(
                                    'Plano Avulso Ativo. O prazo de arrependimento (7 dias) expirou. Seu plano continuará ativo até o término do período contratado.',
                                    style: TextStyle(
                                      color: Colors.white70,
                                      fontSize: 12,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                      ],
                    ),
                  ),
                Expanded(
                  child: _planosDisponiveis.isEmpty
                      ? Center(
                          child: Padding(
                            padding: const EdgeInsets.all(
                              24,
                            ),
                            child: Column(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Text(
                                  'Nenhum plano encontrado para a categoria "$_tipoRealUsuario".',
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    fontSize: 16,
                                  ),
                                  textAlign: TextAlign.center,
                                ),
                                const SizedBox(
                                  height: 16,
                                ),
                                ElevatedButton(
                                  style: ElevatedButton.styleFrom(
                                    backgroundColor: const Color(
                                      0xFFFF8C00,
                                    ),
                                  ),
                                  onPressed: () => _carregarPlanosDoBanco(
                                    _tipoRealUsuario,
                                  ),
                                  child: const Text(
                                    'Recarregar',
                                    style: TextStyle(
                                      color: Colors.white,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                        )
                      : ListView.builder(
                          padding: const EdgeInsets.all(
                            16,
                          ),
                          itemCount: _planosDisponiveis.length,
                          itemBuilder: (
                            context,
                            index,
                          ) {
                            final plano = _planosDisponiveis[index];

                            return _buildCardPlanoUsuario(
                              plano,
                            );
                          },
                        ),
                ),
              ],
            ),
    );
  }

  Widget _buildCardPlanoUsuario(
    Map<String, dynamic> plano,
  ) {
    final String nomePlanoCompleto = plano['nome_plano'] ?? 'Plano';

    String nomeExibicao = nomePlanoCompleto;

    if (nomePlanoCompleto.contains('-')) {
      nomeExibicao = nomePlanoCompleto.split('-').last.trim();
    }

    final double valorAvulso = _toDouble(
      plano['valor'],
    );

    final double valorRecorrente = _toDouble(
      plano['valor_recorrente'],
    );

    // A modalidade recorrente é exibida e pode ser selecionada sempre que
    // houver valor_recorrente. A existência do efi_plan_id é validada
    // somente ao iniciar o checkout recorrente.
    final bool recorrenciaDisponivel = valorRecorrente > 0;

    final int limiteServicos = _toInt(
      plano['limite_servicos'],
    );

    final int limiteFotos = _toInt(
      plano['limite_fotos'],
    );

    final int limiteImagensIa = _toInt(
      plano['limite_imagens_ia'],
    );

    final int qtdeVideos = _toInt(
      plano['qtde_videos'],
    );

    final int limiteDias = _toInt(
      plano['limite_dias'] ?? 30,
    );

    final int limiteDiasRecorrente = _toInt(
      plano['limite_dias_recorrente'] ?? 365,
    );

    final int qtdePostagem = _toInt(
      plano['qtde_postagem'],
    );

    final bool isGratis = _isPlanoGratis(
      plano,
    );

    bool permiteEmail = false;

    final valEmail =
        plano['permite_notificacao_email'] ?? plano['notificacao_email'];

    if (valEmail != null) {
      final st = valEmail.toString().trim().toLowerCase();

      permiteEmail = st == 'true' || st == '1' || st == 'sim';
    }

    bool permitePush = false;

    final valPush = plano['notificacao_push'];

    if (valPush != null) {
      final st = valPush.toString().trim().toLowerCase();

      permitePush = st == 'true' || st == '1' || st == 'sim';
    }

    bool temFacebook = false;

    final valFb = plano['link_facebook'];

    if (valFb != null) {
      final st = valFb.toString().trim().toLowerCase();

      temFacebook = st == 'true' || st == '1' || st == 'sim';
    }

    bool temInstagram = false;

    final valIg = plano['link_instagram'];

    if (valIg != null) {
      final st = valIg.toString().trim().toLowerCase();

      temInstagram = st == 'true' || st == '1' || st == 'sim';
    }

    bool temDestaque = false;

    final varDestaque = plano['destaque_no_feed'];

    if (varDestaque != null) {
      final st = varDestaque.toString().trim().toLowerCase();

      temDestaque = st == 'true' || st == '1' || st == 'sim';
    }

    bool isPlanoAtual = false;

    if (_idPlanoAtivoUsuario != null && plano['id'] != null) {
      if (_idPlanoAtivoUsuario.toString().trim() ==
          plano['id'].toString().trim()) {
        isPlanoAtual = true;
      }
    }

    if (!isPlanoAtual && _planoAtivoUsuario.isNotEmpty) {
      final cleanNome = nomeExibicao.trim().toLowerCase();

      final cleanCompleto = nomePlanoCompleto.trim().toLowerCase();

      if (_planoAtivoUsuario == cleanNome ||
          _planoAtivoUsuario == cleanCompleto ||
          cleanCompleto.contains(
            _planoAtivoUsuario,
          ) ||
          _planoAtivoUsuario.contains(
            cleanNome,
          )) {
        isPlanoAtual = true;
      }
    }

    final bool isPlanoProcessando = _planoEstaProcessando(
      plano,
    );

    bool isRecorrente = isPlanoAtual
        ? _recorrenteAtivo
        : (_escolhaRecorrente[plano['id']] ?? false);

    if (!isPlanoAtual && isRecorrente && !recorrenciaDisponivel) {
      isRecorrente = false;
    }

    final double valorExibido = isRecorrente ? valorRecorrente : valorAvulso;
    final ProductDetails? produtoAppleExibido = _plataformaApple && !isGratis
        ? _produtoAppleDoPlano(plano, recorrente: isRecorrente)
        : null;

    final int diasExibidos = isRecorrente ? limiteDiasRecorrente : limiteDias;

    return Container(
      margin: const EdgeInsets.only(
        bottom: 20,
      ),
      decoration: BoxDecoration(
        color: const Color(
          0xFF101B2B,
        ),
        borderRadius: BorderRadius.circular(
          16,
        ),
        border: Border.all(
          color: isPlanoProcessando
              ? const Color(0xFFFFA726)
              : isPlanoAtual
                  ? Colors.greenAccent
                  : Colors.white12,
          width: (isPlanoAtual || isPlanoProcessando) ? 2.5 : 1,
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(
          20,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                if (temDestaque && !isPlanoAtual)
                  Container(
                    margin: const EdgeInsets.only(
                      bottom: 4,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(
                        0xFFFF8C00,
                      ).withValues(
                        alpha: 0.2,
                      ),
                      borderRadius: BorderRadius.circular(
                        4,
                      ),
                      border: Border.all(
                        color: const Color(
                          0xFFFF8C00,
                        ),
                      ),
                    ),
                    child: const Text(
                      'MAIS POPULAR',
                      style: TextStyle(
                        color: Color(
                          0xFFFF8C00,
                        ),
                        fontSize: 10,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.2,
                      ),
                    ),
                  ),
                if (isPlanoAtual)
                  Container(
                    margin: const EdgeInsets.only(
                      bottom: 4,
                    ),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 10,
                      vertical: 4,
                    ),
                    decoration: BoxDecoration(
                      color: Colors.green,
                      borderRadius: BorderRadius.circular(
                        4,
                      ),
                    ),
                    child: const Text(
                      'PLANO ATUAL',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                        letterSpacing: 1.1,
                      ),
                    ),
                  ),
              ],
            ),

            const SizedBox(
              height: 4,
            ),

            Text(
              nomeExibicao.toUpperCase(),
              style: const TextStyle(
                color: Colors.white,
                fontSize: 20,
                fontWeight: FontWeight.bold,
              ),
            ),

            if (isPlanoAtual || isPlanoProcessando) ...[
              const SizedBox(
                height: 10,
              ),
              _buildStatusPlano(
                ativo: isPlanoAtual && !isPlanoProcessando,
                processando: isPlanoProcessando,
              ),
              if (isPlanoProcessando) ...[
                const SizedBox(
                  height: 7,
                ),
                Text(
                  _efiSubscriptionIdProcessando != null
                      ? 'Aguardando confirmação do pagamento. '
                          'O status será atualizado automaticamente.'
                      : 'Aguardando confirmação do pagamento.',
                  style: const TextStyle(
                    color: Colors.white60,
                    fontSize: 11,
                    height: 1.35,
                  ),
                ),
              ],
            ],

            const SizedBox(
              height: 10,
            ),

            // ===================================================
            // ESCOLHA AVULSO / RECORRENTE
            // ===================================================

            if (valorRecorrente > 0) ...[
              const Text(
                'Escolha a modalidade de pagamento:',
                style: TextStyle(
                  color: Colors.white70,
                  fontSize: 12,
                ),
              ),
              const SizedBox(
                height: 8,
              ),
              Row(
                children: [
                  Expanded(
                    child: ChoiceChip(
                      label: Text(
                        'Avulso (R\$ ${valorAvulso.toStringAsFixed(2).replaceAll('.', ',')})',
                      ),
                      selected: !isRecorrente,
                      selectedColor: const Color(
                        0xFFFF8C00,
                      ),
                      backgroundColor: const Color(
                        0xFF1A2C42,
                      ),
                      disabledColor: const Color(
                        0xFF1A2C42,
                      ),
                      checkmarkColor: Colors.white,
                      side: const BorderSide(
                        color: Colors.white,
                        width: 1,
                      ),
                      labelStyle: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),
                      onSelected: isPlanoAtual
                          ? null
                          : (selected) {
                              setState(() {
                                _escolhaRecorrente[plano['id']] = false;
                              });
                            },
                    ),
                  ),
                  const SizedBox(
                    width: 8,
                  ),
                  Expanded(
                    child: ChoiceChip(
                      label: Text(
                        'Recorrente (R\$ ${valorRecorrente.toStringAsFixed(2).replaceAll('.', ',')})',
                      ),
                      selected: isRecorrente,
                      selectedColor: const Color(
                        0xFFFF8C00,
                      ),
                      backgroundColor: const Color(
                        0xFF1A2C42,
                      ),
                      disabledColor: const Color(
                        0xFF1A2C42,
                      ),
                      checkmarkColor: Colors.white,
                      side: const BorderSide(
                        color: Colors.white,
                        width: 1,
                      ),
                      labelStyle: const TextStyle(
                        color: Colors.white,
                        fontSize: 11,
                        fontWeight: FontWeight.bold,
                      ),

                      // Só habilita quando o plano estiver
                      // configurado na Efí.
                      onSelected: isPlanoAtual
                          ? null
                          : (selected) {
                              setState(() {
                                _escolhaRecorrente[plano['id']] = true;
                              });
                            },
                    ),
                  ),
                ],
              ),
              const SizedBox(
                height: 12,
              ),
            ],

            // ===================================================
            // PREÇO
            // ===================================================

            Row(
              crossAxisAlignment: CrossAxisAlignment.end,
              children: [
                if (produtoAppleExibido == null)
                  const Text(
                    'R\$ ',
                    style: TextStyle(
                      color: Color(0xFFFF8C00),
                      fontSize: 16,
                    ),
                  ),
                Flexible(
                  child: Text(
                    produtoAppleExibido?.price ??
                        valorExibido.toStringAsFixed(2).replaceAll('.', ','),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                    style: const TextStyle(
                      color: Color(0xFFFF8C00),
                      fontSize: 32,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Text(
                  isGratis
                      ? ''
                      : isRecorrente
                          ? ' / mês (recorrente)'
                          : ' / $diasExibidos dias',
                  style: const TextStyle(
                    color: Colors.white54,
                    fontSize: 12,
                  ),
                ),
              ],
            ),

            const Padding(
              padding: EdgeInsets.symmetric(
                vertical: 15,
              ),
              child: Divider(
                color: Colors.white12,
              ),
            ),

            _buildItemBeneficio(
              Icons.work_outline,
              'Até $limiteServicos profissões/serviços',
            ),

            const SizedBox(
              height: 10,
            ),

            _buildItemBeneficio(
              Icons.photo_camera_outlined,
              'Até $limiteFotos fotos por postagem (Meus Trabalhos)',
            ),

            const SizedBox(
              height: 10,
            ),

            _buildItemBeneficio(
              Icons.auto_awesome_outlined,
              'Até $limiteImagensIa imagem(ns) por mês na Jisa IA',
            ),

            const SizedBox(
              height: 10,
            ),

            _buildItemBeneficio(
              Icons.videocam_outlined,
              'Até $qtdeVideos vídeo(s) por postagem (Até 30 seg)',
            ),

            const SizedBox(
              height: 10,
            ),

            _buildItemBeneficio(
              Icons.post_add,
              'Até $qtdePostagem postagem(ns) de demanda(s)',
            ),

            if (!isGratis) ...[
              const SizedBox(
                height: 10,
              ),
              _buildItemBeneficio(
                Icons.calendar_today,
                'Validade de $diasExibidos dias',
              ),
            ],

            if (permiteEmail) ...[
              const SizedBox(
                height: 10,
              ),
              _buildItemBeneficio(
                Icons.email_outlined,
                'Notificações por E-mail incluídas',
              ),
            ],

            if (permitePush) ...[
              const SizedBox(
                height: 10,
              ),
              _buildItemBeneficio(
                Icons.notifications_outlined,
                'Notificações Push incluídas',
              ),
            ],

            if (temFacebook) ...[
              const SizedBox(
                height: 10,
              ),
              _buildItemBeneficio(
                Icons.facebook,
                'Link para o Facebook',
              ),
            ],

            if (temInstagram) ...[
              const SizedBox(
                height: 10,
              ),
              _buildItemBeneficio(
                Icons.camera_alt,
                'Link para o Instagram',
              ),
            ],

            if (temDestaque) ...[
              const SizedBox(
                height: 10,
              ),
              _buildItemBeneficio(
                Icons.star_border,
                'Perfil em Destaque nas buscas',
              ),
            ],

            if (_plataformaApple && !isGratis) ...[
              const SizedBox(height: 10),
              Text(
                produtoAppleExibido != null
                    ? 'Preço fornecido pela App Store.'
                    : (_carregandoProdutosApple
                        ? 'Consultando preço na App Store...'
                        : 'Produto Apple ainda não configurado para compra.'),
                style: const TextStyle(color: Colors.white54, fontSize: 11),
              ),
            ],

            const SizedBox(
              height: 25,
            ),

            // ===================================================
            // CANCELE QUANDO QUISER
            // ===================================================
            //
            // Exibido próximo da ação do plano e somente quando a
            // modalidade recorrente estiver selecionada/ativa.
            // Assim não parece ser uma regra do plano avulso.
            // ===================================================

            if (!isGratis && isRecorrente) ...[
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(
                  bottom: 12,
                ),
                padding: const EdgeInsets.symmetric(
                  horizontal: 14,
                  vertical: 11,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF54E39A).withValues(
                    alpha: 0.08,
                  ),
                  borderRadius: BorderRadius.circular(
                    12,
                  ),
                  border: Border.all(
                    color: const Color(0xFF54E39A).withValues(
                      alpha: 0.38,
                    ),
                  ),
                ),
                child: const Row(
                  children: [
                    Icon(
                      Icons.autorenew_rounded,
                      size: 18,
                      color: Color(0xFF54E39A),
                    ),
                    SizedBox(
                      width: 9,
                    ),
                    Expanded(
                      child: Text(
                        'CANCELE QUANDO QUISER',
                        style: TextStyle(
                          color: Color(0xFF54E39A),
                          fontSize: 11,
                          fontWeight: FontWeight.w800,
                          letterSpacing: 0.75,
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],

            SizedBox(
              width: double.infinity,
              child: ElevatedButton(
                style: ElevatedButton.styleFrom(
                  backgroundColor: Colors.green,
                  disabledBackgroundColor: isPlanoProcessando
                      ? const Color(0xFFFFA726).withValues(
                          alpha: 0.85,
                        )
                      : Colors.green.withValues(
                          alpha: 0.8,
                        ),
                  disabledForegroundColor: Colors.white,
                  padding: const EdgeInsets.symmetric(
                    vertical: 14,
                  ),
                ),
                onPressed: (isPlanoAtual || isPlanoProcessando)
                    ? null
                    : () => _selecionarPlano(
                          plano,
                        ),
                child: Text(
                  isPlanoProcessando
                      ? 'PROCESSANDO'
                      : isPlanoAtual
                          ? 'PLANO ATUAL'
                          : valorExibido == 0
                              ? 'ESCOLHER PLANO GRÁTIS'
                              : 'ASSINAR ESTE PLANO',
                  style: const TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildItemBeneficio(
    IconData icone,
    String texto,
  ) {
    return Row(
      children: [
        Icon(
          icone,
          color: Colors.greenAccent,
          size: 18,
        ),
        const SizedBox(
          width: 10,
        ),
        Expanded(
          child: Text(
            texto,
            style: const TextStyle(
              color: Colors.white70,
              fontSize: 14,
            ),
          ),
        ),
      ],
    );
  }
}
