import 'dart:async';
import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:http/http.dart' as http;
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:webview_flutter/webview_flutter.dart';

class CheckoutEfiTechnicalLogger {
  // Webhook técnico usado pelo app.
  // IMPORTANTE: nunca envie número do cartão, CVV, payment_token,
  // accessToken, CPF ou outros dados sensíveis para este logger.
  static const String _webhookUrl = '';

  static Future<void> enviar({
    required String etapa,
    required Object erro,
    required String origemTipo,
    required String origemId,
    required String tipoPagamento,
    String? detalhe,
  }) async {
    if (_webhookUrl.isEmpty) return;

    try {
      String erroSeguro = erro.toString();
      if (erroSeguro.length > 1200) {
        erroSeguro = '${erroSeguro.substring(0, 1200)}...';
      }

      String detalheSeguro = detalhe?.trim() ?? '';
      if (detalheSeguro.length > 800) {
        detalheSeguro = '${detalheSeguro.substring(0, 800)}...';
      }

      final payload = <String, dynamic>{
        'embeds': [
          {
            'title': '🚨 Falha Técnica - Checkout Efí',
            'color': 16711680,
            'fields': [
              {'name': 'Etapa', 'value': etapa, 'inline': false},
              {
                'name': 'Pagamento',
                'value': tipoPagamento,
                'inline': true,
              },
              {
                'name': 'Origem',
                'value': origemTipo.isEmpty ? 'Não informada' : origemTipo,
                'inline': true,
              },
              {
                'name': 'Origem ID',
                'value': origemId.isEmpty ? 'Não informado' : origemId,
                'inline': false,
              },
              {
                'name': 'Erro técnico',
                'value': '```$erroSeguro```',
                'inline': false,
              },
              if (detalheSeguro.isNotEmpty)
                {
                  'name': 'Detalhes',
                  'value': '```$detalheSeguro```',
                  'inline': false,
                },
            ],
            'timestamp': DateTime.now().toUtc().toIso8601String(),
          }
        ],
      };

      await http
          .post(
            Uri.parse(_webhookUrl),
            headers: {'Content-Type': 'application/json'},
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 8));
    } catch (e) {
      // O logger nunca pode interromper o pagamento.
      debugPrint('[EFÍ][LOGGER] Falha ao enviar log técnico: $e');
    }
  }
}

class ValidadeCartaoFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var text = newValue.text.replaceAll(RegExp(r'\D'), '');

    if (text.length > 4) {
      text = text.substring(0, 4);
    }

    String newText;

    if (text.length >= 3) {
      newText = '${text.substring(0, 2)}/${text.substring(2)}';
    } else {
      newText = text;
    }

    return TextEditingValue(
      text: newText,
      selection: TextSelection.collapsed(
        offset: newText.length,
      ),
    );
  }
}

class NumeroCartaoFormatter extends TextInputFormatter {
  @override
  TextEditingValue formatEditUpdate(
    TextEditingValue oldValue,
    TextEditingValue newValue,
  ) {
    var text = newValue.text.replaceAll(RegExp(r'\D'), '');

    // Limite do checkout: até 16 dígitos.
    if (text.length > 16) {
      text = text.substring(0, 16);
    }

    final buffer = StringBuffer();

    for (int i = 0; i < text.length; i++) {
      buffer.write(text[i]);

      final position = i + 1;

      if (position % 4 == 0 && position != text.length) {
        buffer.write(' ');
      }
    }

    final formatted = buffer.toString();

    return TextEditingValue(
      text: formatted,
      selection: TextSelection.collapsed(
        offset: formatted.length,
      ),
    );
  }
}

///
/// CHECKOUT MODAL
///
class CheckoutModal extends StatefulWidget {
  final String origemTipo;
  final String origemId;
  final bool ehRecorrente;
  final double? valor;
  final String? descricao;

  /// Quando informado, o checkout fica travado em um único método:
  /// 'pix' ou 'cartao'.
  ///
  /// Isso permite abrir o fluxo diretamente no método escolhido
  /// pela tela de planos, sem exibir as abas PIX / Cartão.
  final String? metodoPagamentoFixo;

  const CheckoutModal({
    super.key,
    required this.origemTipo,
    required this.origemId,
    this.ehRecorrente = false,
    this.valor,
    this.descricao,
    this.metodoPagamentoFixo,
  });

  @override
  State<CheckoutModal> createState() => _CheckoutModalState();
}

class _CheckoutModalState extends State<CheckoutModal> {
  // ============================================================
  // CONFIGURAÇÃO EFÍ
  // ============================================================

  /// Identificador de conta da Efí.
  static const String _efiIdentificadorConta =
      '0275df166ff96906972559710c279adc';

  /// Homologação = sandbox
  /// Produção = production
  static const String _efiAmbiente = 'production';

  /// Backend hospedado no Render.
  static const String _backendUrl = 'https://efi-backend-1.onrender.com';

  // ============================================================
  // ESTADO
  // ============================================================

  late String _metodoSelecionado;

  bool _carregandoDados = true;
  bool _carregando = false;
  bool _processandoCartao = false;

  String? _erro;

  String? _qrCodeCopiaECola;

  double? _valor;

  String? _planId;

  dynamic _pedidoId;

  bool _pagamentoAprovado = false;

  // Cartão não é considerado concluído apenas porque a assinatura
  // ficou "active" ou a cobrança ficou "approved/authorized".
  // O plano só pode ser liberado após confirmação definitiva de pagamento.
  bool _pagamentoPendenteCartao = false;
  String? _mensagemPagamentoPendente;

  final Set<String> _logsTecnicosEnviados = <String>{};

  void _registrarErroTecnico(
    String etapa,
    Object erro, {
    String? detalhe,
    String? chave,
  }) {
    final chaveLog = chave ?? etapa;

    // Evita inundar o Discord em rotinas de polling.
    if (_logsTecnicosEnviados.contains(chaveLog)) return;
    _logsTecnicosEnviados.add(chaveLog);

    unawaited(
      CheckoutEfiTechnicalLogger.enviar(
        etapa: etapa,
        erro: erro,
        origemTipo: widget.origemTipo,
        origemId: widget.origemId,
        tipoPagamento: widget.ehRecorrente
            ? 'cartão recorrente'
            : _metodoSelecionado == 'pix'
                ? 'Pix'
                : 'cartão avulso',
        detalhe: detalhe,
      ),
    );
  }

  Timer? _timerPollingPix;
  Timer? _timerPollingCartao;

  int _tentativasPollingPix = 0;
  bool _consultandoStatusPix = false;

  int _tentativasPollingCartao = 0;
  bool _consultandoStatusCartao = false;

  // ============================================================
  // CONTROLLERS
  // ============================================================

  final _emailController = TextEditingController();
  final _cpfController = TextEditingController();
  final _nomeController = TextEditingController();
  final _telefoneController = TextEditingController();

  final _numeroCartaoController = TextEditingController();
  final _validadeController = TextEditingController();
  final _cvvController = TextEditingController();
  final _nomeTitularController = TextEditingController();
  final _cpfTitularController = TextEditingController();

  bool get _temMetodoPagamentoFixo {
    final metodo = widget.metodoPagamentoFixo?.trim().toLowerCase() ?? '';

    return metodo == 'pix' || metodo == 'cartao';
  }

  String _resolverMetodoInicial() {
    final metodoFixo = widget.metodoPagamentoFixo?.trim().toLowerCase() ?? '';

    if (metodoFixo == 'pix' || metodoFixo == 'cartao') {
      return metodoFixo;
    }

    return widget.ehRecorrente ? 'cartao' : 'pix';
  }

  // ============================================================
  // CICLO DE VIDA
  // ============================================================

  @override
  void initState() {
    super.initState();

    _metodoSelecionado = _resolverMetodoInicial();

    _inicializarDadosUsuarioEPlano();
  }

  @override
  void dispose() {
    _timerPollingPix?.cancel();
    _timerPollingCartao?.cancel();

    _emailController.dispose();
    _cpfController.dispose();
    _nomeController.dispose();
    _telefoneController.dispose();

    _numeroCartaoController.dispose();
    _validadeController.dispose();
    _cvvController.dispose();
    _nomeTitularController.dispose();
    _cpfTitularController.dispose();

    super.dispose();
  }

  // ============================================================
  // CPF
  // ============================================================

  bool _validarCPF(String? cpf) {
    if (cpf == null) {
      return false;
    }

    final numbers = cpf.replaceAll(
      RegExp(r'\D'),
      '',
    );

    if (numbers.length != 11) {
      return false;
    }

    if (RegExp(r'^(\d)\1{10}$').hasMatch(numbers)) {
      return false;
    }

    final digits = numbers
        .split('')
        .map(
          (e) => int.parse(e),
        )
        .toList();

    int soma = 0;

    for (int i = 0; i < 9; i++) {
      soma += digits[i] * (10 - i);
    }

    int resto = (soma * 10) % 11;

    if (resto == 10 || resto == 11) {
      resto = 0;
    }

    if (resto != digits[9]) {
      return false;
    }

    soma = 0;

    for (int i = 0; i < 10; i++) {
      soma += digits[i] * (11 - i);
    }

    resto = (soma * 10) % 11;

    if (resto == 10 || resto == 11) {
      resto = 0;
    }

    if (resto != digits[10]) {
      return false;
    }

    return true;
  }

  // ============================================================
  // VALIDAÇÃO DA VALIDADE
  // ============================================================

  bool _validarValidadeCartao(
    String validade,
  ) {
    if (validade.length != 5 || !validade.contains('/')) {
      return false;
    }

    final partes = validade.split('/');

    if (partes.length != 2) {
      return false;
    }

    final mes = int.tryParse(
      partes[0],
    );

    final ano = int.tryParse(
      partes[1],
    );

    if (mes == null || ano == null) {
      return false;
    }

    if (mes < 1 || mes > 12) {
      return false;
    }

    final agora = DateTime.now();

    final anoCompleto = ano < 100 ? 2000 + ano : ano;

    if (anoCompleto < agora.year) {
      return false;
    }

    if (anoCompleto == agora.year && mes < agora.month) {
      return false;
    }

    return true;
  }

  // ============================================================
  // CARREGAR USUÁRIO E PLANO
  // ============================================================

  Future<void> _inicializarDadosUsuarioEPlano() async {
    if (mounted) {
      setState(() {
        _carregandoDados = true;
        _erro = null;
      });
    }

    try {
      final supabase = Supabase.instance.client;

      final user = supabase.auth.currentUser;

      if (user == null) {
        throw 'Usuário não autenticado.';
      }

      // --------------------------------------------------------
      // E-MAIL
      // --------------------------------------------------------

      if (user.email != null && user.email!.trim().isNotEmpty) {
        _emailController.text = user.email!.trim().toLowerCase();
      }

      // --------------------------------------------------------
      // DADOS DO USUÁRIO
      // --------------------------------------------------------

      final dadosUsuario = await supabase
          .from('tab_usuarios')
          .select(
            'cpf, usuario_nome, telefone',
          )
          .eq(
            'id',
            user.id,
          )
          .maybeSingle();

      if (dadosUsuario != null) {
        final cpfBanco = dadosUsuario['cpf'];

        if (cpfBanco != null) {
          final cpfLimpo = cpfBanco.toString().replaceAll(
                RegExp(r'\D'),
                '',
              );

          _cpfController.text = cpfLimpo;

          _cpfTitularController.text = cpfLimpo;
        }

        final nomeBanco = dadosUsuario['usuario_nome'];

        if (nomeBanco != null && nomeBanco.toString().trim().isNotEmpty) {
          final nome = nomeBanco.toString().trim();

          _nomeController.text = nome;

          _nomeTitularController.text = nome;
        }

        final telefoneBanco = dadosUsuario['telefone'];

        if (telefoneBanco != null &&
            telefoneBanco.toString().trim().isNotEmpty) {
          var telefoneLimpo =
              telefoneBanco.toString().replaceAll(RegExp(r'\D'), '');

          // A API Cobranças Efí espera DDD + telefone, sem +55.
          // Se estiver salvo com código do Brasil, removemos o 55.
          if (telefoneLimpo.startsWith('55') &&
              (telefoneLimpo.length == 12 || telefoneLimpo.length == 13)) {
            telefoneLimpo = telefoneLimpo.substring(2);
          }

          if (telefoneLimpo.length == 10 || telefoneLimpo.length == 11) {
            _telefoneController.text = telefoneLimpo;
          }
        }
      }

      // --------------------------------------------------------
      // VALOR DIRETO
      // --------------------------------------------------------

      if (widget.valor != null && widget.valor! > 0) {
        _valor = widget.valor;
      } else {
        // ------------------------------------------------------
        // BUSCAR PLANO
        // ------------------------------------------------------

        final plano = await supabase
            .from('tab_planos')
            .select()
            .eq(
              'id',
              widget.origemId,
            )
            .maybeSingle();

        if (plano != null) {
          final valorAvulso = (plano['valor'] as num?)?.toDouble() ?? 0.0;

          final valorRecorrente =
              (plano['valor_recorrente'] as num?)?.toDouble() ?? 0.0;

          // ----------------------------------------------------
          // ID DO PLANO EFÍ
          // ----------------------------------------------------

          if (plano['efi_plan_id'] != null) {
            _planId = plano['efi_plan_id'].toString();
          } else if (plano['plan_id'] != null) {
            _planId = plano['plan_id'].toString();
          }

          // ----------------------------------------------------
          // VALOR
          // ----------------------------------------------------

          if (widget.ehRecorrente && valorRecorrente > 0) {
            _valor = valorRecorrente;
          } else {
            _valor = valorAvulso;
          }
        }
      }
    } catch (e) {
      _registrarErroTecnico(
        'INICIALIZAÇÃO DOS DADOS DO CHECKOUT',
        e,
        detalhe: 'Falha ao carregar usuário/plano no Supabase.',
      );

      debugPrint(
        'Erro ao inicializar dados do checkout: $e',
      );

      if (mounted) {
        setState(() {
          _erro = 'Erro ao carregar os dados do pagamento.';
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _carregandoDados = false;
        });
      }
    }
  }

  // ============================================================
  // BANDEIRA DO CARTÃO
  // ============================================================

  String _identificarBandeira(
    String numeroCartao,
  ) {
    final clean = numeroCartao.replaceAll(
      RegExp(r'\D'),
      '',
    );

    // Esta função é apenas fallback/diagnóstico. A identificação usada para
    // gerar o payment_token é feita pela biblioteca oficial da Efí na WebView.

    // ELO precisa ser verificado ANTES de Visa, pois vários BINs Elo começam
    // com 4 e seriam classificados incorretamente como Visa.
    if (RegExp(
      r'^(4011|431274|438935|451416|457393|457631|504175|506699|5067|5090|627780|636297|636368|6500|6504|6509|6516|6550)',
    ).hasMatch(clean)) {
      return 'elo';
    }

    // HIPERCARD
    if (RegExp(
      r'^(384100|384140|384160|606282|637095|637568|637599|637609|637612)',
    ).hasMatch(clean)) {
      return 'hipercard';
    }

    // VISA
    if (clean.startsWith('4')) {
      return 'visa';
    }

    // MASTERCARD: 51-55 ou 2221-2720.
    if (RegExp(r'^5[1-5]').hasMatch(clean)) {
      return 'mastercard';
    }

    if (clean.length >= 4) {
      final prefixo4 = int.tryParse(clean.substring(0, 4));

      if (prefixo4 != null && prefixo4 >= 2221 && prefixo4 <= 2720) {
        return 'mastercard';
      }
    }

    // AMEX
    if (RegExp(r'^(34|37)').hasMatch(clean)) {
      return 'amex';
    }

    // A biblioteca oficial da Efí será a autoridade final.
    return '';
  }

  // ============================================================
  // POLLING PIX
  // ============================================================
  //
  // Depois que /gerar-pix retorna o txid, o app consulta
  // GET /status-pix/:txid no backend.
  //
  // O backend é responsável por:
  // - consultar a cobrança na Efí;
  // - identificar quando ela estiver CONCLUIDA;
  // - salvar pix_e2e_id em tab_pagamentos_avulsos;
  // - atualizar status para "pago".
  //
  // Isso também permite testar corretamente em homologação.
  // ============================================================

  void _iniciarPollingPix() {
    _timerPollingPix?.cancel();

    _tentativasPollingPix = 0;
    _consultandoStatusPix = false;

    final txid = _pedidoId?.toString().trim() ?? '';

    if (txid.isEmpty) {
      debugPrint(
        'Polling Pix não iniciado: txid vazio.',
      );
      return;
    }

    debugPrint(
      'Iniciando polling Pix. txid=$txid',
    );

    // Faz uma primeira consulta rapidamente.
    Future.delayed(
      const Duration(
        seconds: 2,
      ),
      () {
        if (mounted && !_pagamentoAprovado) {
          _consultarStatusPix(
            txid,
          );
        }
      },
    );

    // Depois consulta a cada 3 segundos.
    _timerPollingPix = Timer.periodic(
      const Duration(
        seconds: 3,
      ),
      (timer) async {
        if (!mounted) {
          timer.cancel();
          return;
        }

        if (_pagamentoAprovado) {
          timer.cancel();
          return;
        }

        _tentativasPollingPix++;

        // Aproximadamente 5 minutos de espera.
        if (_tentativasPollingPix > 100) {
          timer.cancel();

          debugPrint(
            'Polling Pix encerrado por tempo limite. '
            'txid=$txid',
          );

          if (mounted) {
            setState(() {
              _erro = 'O Pix ainda não foi confirmado. '
                  'Se você já efetuou o pagamento, aguarde alguns instantes '
                  'e abra novamente a tela de planos antes de gerar outra cobrança.';
            });
          }

          return;
        }

        await _consultarStatusPix(
          txid,
        );
      },
    );
  }

  Future<void> _consultarStatusPix(
    String txid,
  ) async {
    if (_consultandoStatusPix) {
      return;
    }

    final txidLimpo = txid.trim();

    if (txidLimpo.isEmpty) {
      return;
    }

    _consultandoStatusPix = true;

    try {
      final supabase = Supabase.instance.client;

      final session = supabase.auth.currentSession;

      if (session == null || session.accessToken.trim().isEmpty) {
        debugPrint(
          'Não foi possível consultar o Pix: sessão Supabase ausente.',
        );
        return;
      }

      final response = await http.get(
        Uri.parse(
          '$_backendUrl/status-pix/${Uri.encodeComponent(txidLimpo)}',
        ),
        headers: {
          'Content-Type': 'application/json',
          'Authorization': 'Bearer ${session.accessToken}',
        },
      ).timeout(
        const Duration(
          seconds: 30,
        ),
      );

      Map<String, dynamic> data = {};

      try {
        final decoded = jsonDecode(
          response.body,
        );

        if (decoded is Map) {
          data = Map<String, dynamic>.from(
            decoded,
          );
        }
      } catch (e) {
        _registrarErroTecnico(
          'RESPOSTA INVÁLIDA NO STATUS DO PIX',
          e,
          detalhe: 'HTTP ${response.statusCode}',
          chave: 'status_pix_json_invalido',
        );

        debugPrint(
          'Resposta inválida ao consultar status Pix. '
          'HTTP ${response.statusCode}: ${response.body}',
        );
        return;
      }

      // 404 pode acontecer nos primeiros instantes se o registro
      // ainda estiver sendo persistido. O polling continua.
      if (response.statusCode == 404) {
        debugPrint(
          'Pagamento Pix ainda não localizado pelo backend. '
          'txid=$txidLimpo',
        );
        return;
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        if (response.statusCode >= 500) {
          _registrarErroTecnico(
            'FALHA DO BACKEND AO CONSULTAR STATUS DO PIX',
            'HTTP ${response.statusCode}',
            detalhe:
                (data['error'] ?? data['message'] ?? 'Erro interno do servidor')
                    .toString(),
            chave: 'status_pix_http_5xx',
          );
        }

        debugPrint(
          'Consulta Pix retornou HTTP ${response.statusCode}: '
          '${data['error'] ?? data['message'] ?? response.body}',
        );
        return;
      }

      final bool pago = data['pago'] == true;

      final status = data['status']?.toString().trim().toLowerCase() ?? '';

      final statusEfi = data['status_efi']?.toString().trim() ?? '';

      final e2eId = data['e2e_id']?.toString().trim() ?? '';

      debugPrint(
        'Status Pix: '
        'txid=$txidLimpo '
        '| pago=$pago '
        '| status=$status '
        '| status_efi=$statusEfi '
        '| e2e_id=${e2eId.isEmpty ? '-' : e2eId}',
      );

      if (pago || status == 'pago' || status == 'paid') {
        // A confirmação veio do backend, que por sua vez consulta a Efí.
        // Só neste ponto o checkout pode ser encerrado como aprovado.
        _timerPollingPix?.cancel();

        if (!mounted) {
          return;
        }

        setState(() {
          _erro = null;
          _pagamentoAprovado = true;
        });

        debugPrint(
          'Pix confirmado com sucesso. '
          'txid=$txidLimpo '
          '| e2e_id=${e2eId.isEmpty ? '-' : e2eId}',
        );

        // Não fecha automaticamente.
        // A interface muda para a tela de sucesso e o usuário confirma
        // conscientemente tocando em OK.
        return;
      }
    } on TimeoutException catch (e) {
      _registrarErroTecnico(
        'TIMEOUT AO CONSULTAR STATUS DO PIX',
        e,
        detalhe: 'Endpoint: /status-pix | timeout=30s',
        chave: 'status_pix_timeout',
      );

      debugPrint(
        'Timeout ao consultar status do Pix. '
        'O polling continuará.',
      );
    } catch (e) {
      _registrarErroTecnico(
        'ERRO INTERNO AO CONSULTAR STATUS DO PIX',
        e,
        chave: 'status_pix_excecao',
      );

      debugPrint(
        'Erro ao consultar status Pix: $e',
      );
    } finally {
      _consultandoStatusPix = false;
    }
  }

  // ============================================================
  // PAGAMENTO PIX
  // ============================================================

  Future<void> _processarPagamentoPix() async {
    _timerPollingPix?.cancel();

    final email = _emailController.text.trim().toLowerCase();

    final cpf = _cpfController.text.replaceAll(
      RegExp(r'\D'),
      '',
    );

    final nome = _nomeController.text.trim().isNotEmpty
        ? _nomeController.text.trim()
        : 'Cliente Ache Obra';

    final valorEnvio = _valor ?? widget.valor ?? 0.0;

    // ----------------------------------------------------------
    // VALIDAÇÕES
    // ----------------------------------------------------------

    if (email.isEmpty || !email.contains('@')) {
      setState(() {
        _erro = 'Informe um e-mail válido.';
      });
      return;
    }

    if (!_validarCPF(cpf)) {
      setState(() {
        _erro = 'CPF do pagador inválido. Informe um CPF válido.';
      });
      return;
    }

    if (valorEnvio <= 0) {
      setState(() {
        _erro = 'O valor do pagamento deve ser maior que zero.';
      });
      return;
    }

    setState(() {
      _carregando = true;
      _erro = null;
      _qrCodeCopiaECola = null;
      _pedidoId = null;
      _pagamentoAprovado = false;
    });

    try {
      final user = Supabase.instance.client.auth.currentUser;

      if (user == null) {
        throw 'Usuário não autenticado.';
      }

      final session = Supabase.instance.client.auth.currentSession;

      if (session == null || session.accessToken.trim().isEmpty) {
        throw 'Sua sessão expirou. Entre novamente para gerar o Pix.';
      }

      final payloadPix = <String, dynamic>{
        'usuario_id': user.id,
        'origem_tipo': widget.origemTipo,
        'origem_id': widget.origemId,
        'valor': valorEnvio,
        'cpf': cpf,
        'nome': nome,
        'descricao': widget.descricao ?? 'Pagamento Ache Obra',
      };

      debugPrint(
        'Gerando Pix no backend. '
        'usuario_id=${user.id} '
        '| origem_tipo=${widget.origemTipo} '
        '| origem_id=${widget.origemId} '
        '| valor=$valorEnvio',
      );

      final uriGerarPix = Uri.parse(
        '$_backendUrl/gerar-pix',
      );

      final inicioRequisicaoPix = DateTime.now();

      debugPrint(
        '========================================',
      );
      debugPrint(
        '[PIX][CHECKOUT] INICIANDO /gerar-pix',
      );
      debugPrint(
        '[PIX][CHECKOUT] URL: $uriGerarPix',
      );
      debugPrint(
        '[PIX][CHECKOUT] usuario_id=${user.id}',
      );
      debugPrint(
        '[PIX][CHECKOUT] origem_tipo=${widget.origemTipo}',
      );
      debugPrint(
        '[PIX][CHECKOUT] origem_id=${widget.origemId}',
      );
      debugPrint(
        '[PIX][CHECKOUT] valor=$valorEnvio',
      );
      debugPrint(
        '[PIX][CHECKOUT] horario_local=${inicioRequisicaoPix.toIso8601String()}',
      );
      debugPrint(
        '========================================',
      );

      final response = await http
          .post(
            uriGerarPix,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${session.accessToken}',
            },
            body: jsonEncode(
              payloadPix,
            ),
          )
          .timeout(
            const Duration(
              seconds: 45,
            ),
          );

      debugPrint(
        '========================================',
      );
      debugPrint(
        '[PIX][CHECKOUT] RESPOSTA /gerar-pix',
      );
      debugPrint(
        '[PIX][CHECKOUT] HTTP ${response.statusCode}',
      );
      debugPrint(
        '[PIX][CHECKOUT] body=${response.body}',
      );
      debugPrint(
        '[PIX][CHECKOUT] duracao_ms=${DateTime.now().difference(inicioRequisicaoPix).inMilliseconds}',
      );
      debugPrint(
        '========================================',
      );

      Map<String, dynamic> data = {};

      try {
        final decoded = jsonDecode(
          response.body,
        );

        if (decoded is Map) {
          data = Map<String, dynamic>.from(
            decoded,
          );
        }
      } catch (e) {
        _registrarErroTecnico(
          'RESPOSTA INVÁLIDA AO GERAR PIX',
          e,
          detalhe: 'HTTP ${response.statusCode}',
        );
        throw 'Resposta inválida do servidor.';
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        final erroServidor = data['error'] ??
            data['error_description'] ??
            data['message'] ??
            'Erro desconhecido';

        if (response.statusCode >= 500) {
          _registrarErroTecnico(
            'FALHA INTERNA DO BACKEND AO GERAR PIX',
            'HTTP ${response.statusCode}',
            detalhe: erroServidor.toString(),
          );
        }

        throw 'Erro no servidor (${response.statusCode}): $erroServidor';
      }

      if (data['error'] != null) {
        throw data['error'].toString();
      }

      // --------------------------------------------------------
      // COMPATIBILIDADE ENTRE VERSÕES DO BACKEND
      // --------------------------------------------------------
      //
      // O backend antigo do Ache Obra retornava apenas:
      //   success, txid e pix_copia_e_cola.
      //
      // O backend novo também retorna:
      //   registro_pagamento_salvo,
      //   pagamento_avulso_id,
      //   erro_registro_pagamento.
      //
      // Antes, a ausência de "registro_pagamento_salvo" era tratada
      // como false. Isso fazia um backend antigo, mesmo tendo criado
      // o Pix corretamente na Efí, cair na mensagem:
      // "O Pix foi gerado, mas o pagamento não foi registrado".
      //
      // Agora só consideramos falha de registro quando o backend
      // NOVO informa explicitamente:
      //   registro_pagamento_salvo == false
      // --------------------------------------------------------

      final bool backendInformouRegistroPagamento = data.containsKey(
        'registro_pagamento_salvo',
      );

      final bool registroPagamentoSalvo =
          data['registro_pagamento_salvo'] == true;

      final pagamentoAvulsoId = data['pagamento_avulso_id']?.toString().trim();

      final erroRegistroPagamento = data['erro_registro_pagamento'];

      debugPrint(
        '[PIX][CHECKOUT] Resposta de geração Pix: '
        'backend_informou_registro=$backendInformouRegistroPagamento '
        '| registro_salvo=$registroPagamentoSalvo '
        '| pagamento_avulso_id=${pagamentoAvulsoId ?? '-'} '
        '| txid=${data['txid'] ?? '-'} '
        '| erro_registro=${erroRegistroPagamento ?? '-'}',
      );

      if (backendInformouRegistroPagamento && !registroPagamentoSalvo) {
        _registrarErroTecnico(
          'PIX CRIADO MAS NÃO REGISTRADO NO SISTEMA',
          erroRegistroPagamento ?? 'registro_pagamento_salvo=false',
          detalhe:
              'A Efí criou o Pix, mas o backend não confirmou o registro local.',
        );

        throw erroRegistroPagamento != null
            ? 'O Pix foi criado na Efí, mas o backend não conseguiu registrar '
                'o pagamento no sistema: $erroRegistroPagamento'
            : 'O Pix foi criado na Efí, mas o backend informou que o pagamento '
                'não foi registrado em tab_pagamentos_avulsos. '
                'Não efetue outro pagamento até verificar o servidor.';
      }

      if (!backendInformouRegistroPagamento) {
        debugPrint(
          '[PIX][CHECKOUT][ATENÇÃO] O backend respondeu no formato antigo. '
          'O Pix será exibido normalmente, mas pagamento_avulso_id e '
          'registro_pagamento_salvo não vieram na resposta. '
          'Confira se o server.js novo está realmente publicado no Render.',
        );
      }

      final copiaECola =
          data['pix_copia_e_cola'] ?? data['pixCopiaECola'] ?? data['qr_code'];

      if (copiaECola == null || copiaECola.toString().trim().isEmpty) {
        _registrarErroTecnico(
          'BACKEND NÃO RETORNOU O CÓDIGO PIX',
          'pix_copia_e_cola ausente ou vazio.',
        );
        throw 'O servidor não retornou o código Pix.';
      }

      final pedidoId = data['txid'] ?? data['order_id'] ?? data['pedido_id'];

      final txid = pedidoId?.toString().trim() ?? '';

      if (txid.isEmpty) {
        _registrarErroTecnico(
          'BACKEND NÃO RETORNOU TXID DO PIX',
          'Pix criado sem txid utilizável na resposta.',
        );
        throw 'O servidor gerou o Pix, mas não retornou o txid necessário para confirmar o pagamento.';
      }

      if (mounted) {
        setState(() {
          _qrCodeCopiaECola = copiaECola.toString();

          _pedidoId = txid;
        });
      }

      _iniciarPollingPix();
    } on TimeoutException catch (e) {
      _registrarErroTecnico(
        'TIMEOUT AO GERAR PIX',
        e,
        detalhe: 'Endpoint: /gerar-pix | timeout=45s',
      );

      debugPrint(
        '[PIX][CHECKOUT] TIMEOUT: o backend não respondeu /gerar-pix em até 45 segundos.',
      );

      if (mounted) {
        setState(() {
          _erro = 'O servidor demorou mais de 45 segundos para responder. '
              'Não gere outro Pix imediatamente. Verifique o Render antes de tentar novamente.';
        });
      }
    } catch (e) {
      debugPrint(
        '[PIX][CHECKOUT] ERRO em /gerar-pix: $e',
      );

      if (mounted) {
        setState(() {
          _erro = e.toString().replaceFirst(
                'Exception: ',
                '',
              );
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _carregando = false;
        });
      }
    }
  }

  // ============================================================
  // TOKENIZAÇÃO DO CARTÃO
  // ============================================================

  Future<String?> _obterPaymentToken() async {
    if (_efiIdentificadorConta.trim().isEmpty ||
        _efiIdentificadorConta == 'COLOQUE_AQUI_SEU_IDENTIFICADOR_DE_CONTA') {
      throw 'Configure o Identificador de conta da Efí no código do aplicativo.';
    }

    final numero = _numeroCartaoController.text.replaceAll(
      RegExp(r'\D'),
      '',
    );

    final validade = _validadeController.text.trim();

    final cvv = _cvvController.text.trim();

    final nome = _nomeTitularController.text.trim();

    final cpf = _cpfTitularController.text.replaceAll(
      RegExp(r'\D'),
      '',
    );

    if (numero.length < 13 || numero.length > 16) {
      throw 'Número do cartão inválido.';
    }

    if (!_validarValidadeCartao(
      validade,
    )) {
      throw 'A validade do cartão é inválida ou está vencida.';
    }

    if (cvv.length < 3 || cvv.length > 4) {
      throw 'Informe corretamente o CVV do cartão.';
    }

    if (nome.isEmpty) {
      throw 'Informe o nome impresso no cartão.';
    }

    if (!_validarCPF(cpf)) {
      throw 'CPF do titular inválido.';
    }

    final partes = validade.split('/');

    final mes = partes[0].trim();

    final anoInformado = partes[1].trim();

    final ano = anoInformado.length == 2 ? '20$anoInformado' : anoInformado;

    // A identificação definitiva da bandeira é feita dentro da WebView
    // pela biblioteca oficial payment-token-efi da própria Efí.
    // Mantemos este valor apenas por compatibilidade com a classe existente.
    final bandeira = _identificarBandeira(
      numero,
    );

    debugPrint(
      'Iniciando tokenização Efí.',
    );

    // ----------------------------------------------------------
    // WEBVIEW DA EFÍ
    // ----------------------------------------------------------

    final paymentToken = await Navigator.of(context).push<String?>(
      MaterialPageRoute(
        fullscreenDialog: true,
        builder: (_) {
          return EfiTokenizacaoPage(
            identificadorConta: _efiIdentificadorConta,
            ambiente: _efiAmbiente,
            bandeira: bandeira,
            numero: numero,
            cvv: cvv,
            mes: mes,
            ano: ano,
            nomeTitular: nome,
            cpfTitular: cpf,
            onErroTecnico: (etapa, erro, detalhe) {
              _registrarErroTecnico(
                etapa,
                erro,
                detalhe: detalhe,
              );
            },
          );
        },
      ),
    );

    if (paymentToken == null || paymentToken.trim().isEmpty) {
      throw 'A Efí não retornou o token de pagamento.';
    }

    debugPrint(
      'Payment token recebido com sucesso.',
    );

    return paymentToken;
  }

  // ============================================================
  // RECUPERAÇÃO DE PAGAMENTO AVULSO APÓS TIMEOUT
  // ============================================================
  //
  // Se a Efí aprovar a cobrança, mas o backend demorar para responder
  // ao aplicativo, o Flutter consulta tab_pagamentos_avulsos antes de
  // informar falha ao usuário. Isso evita o cenário:
  //
  //   cartão cobrado -> timeout no app -> usuário tenta pagar de novo.
  //
  // A recuperação é usada somente para pagamento avulso no cartão.
  // ============================================================

  Future<Map<String, dynamic>?> _recuperarPagamentoAvulsoAprovado({
    required String usuarioId,
    required DateTime inicioTentativa,
  }) async {
    final supabase = Supabase.instance.client;

    // Aceita uma pequena margem anterior ao início da tentativa para
    // diferenças de relógio entre dispositivo, Render e banco.
    final limiteInferior = inicioTentativa
        .subtract(
          const Duration(
            minutes: 2,
          ),
        )
        .toUtc();

    for (int tentativa = 1; tentativa <= 8; tentativa++) {
      try {
        debugPrint(
          'Recuperação de pagamento avulso após timeout. '
          'Tentativa $tentativa de 8.',
        );

        final response = await supabase
            .from('tab_pagamentos_avulsos')
            .select(
              'id, usuario_id, origem_tipo, origem_id, tipo_pagamento, '
              'valor, efi_charge_id, status, data_pagamento, created_at',
            )
            .eq(
              'usuario_id',
              usuarioId,
            )
            .eq(
              'origem_id',
              widget.origemId,
            )
            .eq(
              'tipo_pagamento',
              'cartao',
            )
            .order(
              'data_pagamento',
              ascending: false,
            )
            .limit(
              5,
            );

        for (final item in response) {
          final pagamento = Map<String, dynamic>.from(
            item,
          );

          final status =
              pagamento['status']?.toString().trim().toLowerCase() ?? '';

          final dataRaw =
              pagamento['data_pagamento'] ?? pagamento['created_at'];

          final dataPagamento = dataRaw != null
              ? DateTime.tryParse(
                  dataRaw.toString(),
                )
              : null;

          if (dataPagamento == null) {
            continue;
          }

          final dataUtc = dataPagamento.toUtc();

          // Só recupera como pagamento concluído quando o banco já
          // indicar pagamento definitivo. "approved" e "authorized"
          // não liberam mais o plano.
          final statusAprovado =
              status == 'pago' || status == 'paid' || status == 'settled';

          if (statusAprovado &&
              !dataUtc.isBefore(
                limiteInferior,
              )) {
            debugPrint(
              'Pagamento recuperado com sucesso após timeout. '
              'ID=${pagamento['id']} '
              '| charge_id=${pagamento['efi_charge_id']} '
              '| status=$status',
            );

            return pagamento;
          }
        }
      } catch (e) {
        debugPrint(
          'Erro ao tentar recuperar pagamento avulso '
          '(tentativa $tentativa): $e',
        );
      }

      if (tentativa < 8) {
        await Future.delayed(
          const Duration(
            seconds: 2,
          ),
        );
      }
    }

    return null;
  }

  // ============================================================
  // ASSINATURA RECORRENTE ATUAL
  // ============================================================
  //
  // Antes de enviar um pagamento recorrente, verificamos se o
  // usuário já possui uma assinatura considerada vigente.
  //
  // Se possuir:
  //   -> /trocar-assinatura
  //
  // Se não possuir:
  //   -> /cobrar-assinatura
  //
  // Para decidir se existe uma assinatura recorrente ATUAL, somente uma
  // assinatura já paga e ainda ativo/inadimplente conta como vigente.
  // pagamento_pendente é tentativa de compra, não plano atual.
  // ============================================================

  Future<bool> _possuiAssinaturaRecorrenteAtual(
    String usuarioId,
  ) async {
    final supabase = Supabase.instance.client;

    final response = await supabase
        .from('tab_assinaturas')
        .select(
          'plano_id, efi_subscription_id, status_assinatura, '
          'ultimo_status_efi, data_ultimo_pagamento, created_at',
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
          20,
        );

    for (final item in response) {
      final registro = Map<String, dynamic>.from(
        item,
      );

      final status =
          registro['status_assinatura']?.toString().trim().toLowerCase() ?? '';

      final ultimoStatusEfi =
          registro['ultimo_status_efi']?.toString().trim().toLowerCase() ?? '';

      final dataUltimoPagamento =
          registro['data_ultimo_pagamento']?.toString().trim() ?? '';

      final subscriptionId =
          registro['efi_subscription_id']?.toString().trim() ?? '';

      // "pagamento_pendente" representa uma tentativa nova ainda não paga.
      // Ela NÃO pode ser tratada como assinatura recorrente atual para decidir
      // entre /cobrar-assinatura e /trocar-assinatura.
      //
      // Uma assinatura atual precisa ter sido efetivamente paga pelo menos uma
      // vez e continuar em estado ativo/inadimplente.
      final possuiPagamentoConfirmado = dataUltimoPagamento.isNotEmpty ||
          ultimoStatusEfi == 'paid' ||
          ultimoStatusEfi == 'settled' ||
          ultimoStatusEfi == 'pago';

      final vigente = (status == 'ativo' || status == 'inadimplente') &&
          possuiPagamentoConfirmado &&
          subscriptionId.isNotEmpty;

      if (vigente) {
        debugPrint(
          'Assinatura recorrente atual confirmada. '
          'status=$status '
          '| ultimo_status_efi=$ultimoStatusEfi '
          '| plano_id=${registro['plano_id'] ?? '-'} '
          '| subscription_id=$subscriptionId',
        );

        return true;
      }

      if (status == 'pagamento_pendente') {
        debugPrint(
          'Tentativa recorrente pendente encontrada, mas ela não será '
          'tratada como plano recorrente atual. '
          'plano_id=${registro['plano_id'] ?? '-'} '
          '| subscription_id=${subscriptionId.isEmpty ? '-' : subscriptionId}',
        );
      }
    }

    debugPrint(
      'Nenhuma assinatura recorrente atual paga encontrada para o usuário.',
    );

    return false;
  }

  // ============================================================
  // CONFIRMAÇÃO DEFINITIVA DO CARTÃO RECORRENTE
  // ============================================================
  //
  // IMPORTANTE:
  // "active" é status da assinatura e NÃO prova que a primeira
  // cobrança já foi paga.
  //
  // Da mesma forma, "approved" / "authorized" não são tratados
  // aqui como pagamento liquidado.
  //
  // Para liberar o plano recorrente, exigimos no Supabase:
  // - a assinatura do plano selecionado;
  // - status_assinatura = ativo;
  // - ultimo_status_efi = paid ou settled;
  // - data_ultimo_pagamento preenchida.
  //
  // O webhook do backend é quem deve atualizar esses campos depois
  // que a Efí confirmar realmente a cobrança.
  // ============================================================

  bool _statusCartaoDefinitivamentePago(
    String status,
  ) {
    final normalizado = status.trim().toLowerCase();

    return normalizado == 'paid' ||
        normalizado == 'settled' ||
        normalizado == 'pago';
  }

  String _extrairStatusPrimeiraCobrancaRecorrente(
    Map<String, dynamic> data,
  ) {
    final chargeDireto = data['charge'];

    if (chargeDireto is Map && chargeDireto['status'] != null) {
      return chargeDireto['status'].toString().trim().toLowerCase();
    }

    final dadosInternos = data['data'];

    if (dadosInternos is Map) {
      final chargeInterno = dadosInternos['charge'];

      if (chargeInterno is Map && chargeInterno['status'] != null) {
        return chargeInterno['status'].toString().trim().toLowerCase();
      }
    }

    return '';
  }

  void _iniciarPollingCartaoRecorrente(
    String usuarioId,
  ) {
    _timerPollingCartao?.cancel();

    _tentativasPollingCartao = 0;
    _consultandoStatusCartao = false;

    // Primeira consulta rapidamente.
    Future.delayed(
      const Duration(
        seconds: 2,
      ),
      () {
        if (mounted &&
            widget.ehRecorrente &&
            !_pagamentoAprovado &&
            _pagamentoPendenteCartao) {
          _consultarConfirmacaoCartaoRecorrente(
            usuarioId,
          );
        }
      },
    );

    // Continua consultando enquanto a Efí ainda não confirmou pagamento.
    _timerPollingCartao = Timer.periodic(
      const Duration(
        seconds: 3,
      ),
      (timer) async {
        if (!mounted) {
          timer.cancel();
          return;
        }

        if (_pagamentoAprovado || !_pagamentoPendenteCartao) {
          timer.cancel();
          return;
        }

        _tentativasPollingCartao++;

        // Aproximadamente 5 minutos.
        if (_tentativasPollingCartao > 100) {
          timer.cancel();

          if (mounted) {
            setState(() {
              _mensagemPagamentoPendente =
                  'A cobrança foi criada, mas a Efí ainda não confirmou '
                  'o pagamento. Seu plano não foi alterado.\\n\\n'
                  'Você pode fechar esta tela e verificar novamente mais tarde. '
                  'Não faça um novo pagamento enquanto esta cobrança estiver pendente.';
            });
          }

          return;
        }

        await _consultarConfirmacaoCartaoRecorrente(
          usuarioId,
        );
      },
    );
  }

  Future<void> _consultarConfirmacaoCartaoRecorrente(
    String usuarioId,
  ) async {
    if (_consultandoStatusCartao || !widget.ehRecorrente) {
      return;
    }

    _consultandoStatusCartao = true;

    try {
      final supabase = Supabase.instance.client;

      final response = await supabase
          .from('tab_assinaturas')
          .select(
            'id, usuario_id, plano_id, efi_subscription_id, efi_charge_id, '
            'status_assinatura, ultimo_status_efi, data_ultimo_pagamento, created_at',
          )
          .eq(
            'usuario_id',
            usuarioId,
          )
          .eq(
            'plano_id',
            widget.origemId,
          )
          .order(
            'created_at',
            ascending: false,
          )
          .limit(
            5,
          );

      if (response.isEmpty) {
        debugPrint(
          'Cartão recorrente: assinatura ainda não apareceu em tab_assinaturas.',
        );
        return;
      }

      for (final item in response) {
        final assinatura = Map<String, dynamic>.from(
          item,
        );

        final statusAssinatura =
            assinatura['status_assinatura']?.toString().trim().toLowerCase() ??
                '';

        final ultimoStatusEfi =
            assinatura['ultimo_status_efi']?.toString().trim().toLowerCase() ??
                '';

        final dataUltimoPagamento =
            assinatura['data_ultimo_pagamento']?.toString().trim() ?? '';

        final confirmado = statusAssinatura == 'ativo' &&
            _statusCartaoDefinitivamentePago(
              ultimoStatusEfi,
            ) &&
            dataUltimoPagamento.isNotEmpty;

        debugPrint(
          'Cartão recorrente: verificando confirmação no banco. '
          'status_assinatura=$statusAssinatura '
          '| ultimo_status_efi=$ultimoStatusEfi '
          '| data_ultimo_pagamento=${dataUltimoPagamento.isEmpty ? '-' : dataUltimoPagamento}',
        );

        if (confirmado) {
          _timerPollingCartao?.cancel();

          if (!mounted) {
            return;
          }

          setState(() {
            _erro = null;
            _pagamentoPendenteCartao = false;
            _mensagemPagamentoPendente = null;
            _pagamentoAprovado = true;
          });

          debugPrint(
            'Cartão recorrente confirmado definitivamente pela Efí/Supabase.',
          );

          return;
        }
      }
    } catch (e) {
      _registrarErroTecnico(
        'ERRO AO CONSULTAR CONFIRMAÇÃO DO CARTÃO RECORRENTE',
        e,
        chave: 'polling_cartao_recorrente',
      );

      debugPrint(
        'Erro ao consultar confirmação do cartão recorrente: $e',
      );
    } finally {
      _consultandoStatusCartao = false;
    }
  }

  // ============================================================
  // TRATAMENTO AMIGÁVEL DE RECUSA DO CARTÃO
  // ============================================================

  bool _ehRecusaNormalDeCartao({
    required int httpStatus,
    required String status,
    required String mensagem,
  }) {
    final texto = '${status.toLowerCase()} ${mensagem.toLowerCase()}';

    const statusRecusados = <String>{
      'refused',
      'declined',
      'denied',
      'rejected',
      'recusado',
      'cancelled',
      'canceled',
    };

    if (statusRecusados.contains(status.trim().toLowerCase())) {
      return true;
    }

    const sinaisDeRecusa = <String>[
      'recus',
      'declin',
      'denied',
      'rejected',
      'não aprovado',
      'nao aprovado',
      'insufficient',
      'insuficiente',
      'sem limite',
      'limite',
      'do not honor',
      'not honor',
      'cartão bloqueado',
      'cartao bloqueado',
      'card blocked',
      'transação não autorizada',
      'transacao nao autorizada',
      'não autorizada',
      'nao autorizada',
    ];

    if (sinaisDeRecusa.any(texto.contains)) {
      return true;
    }

    // 402/422 são frequentemente usados pelo backend para regras de negócio,
    // mas só os tratamos como recusa quando a mensagem/status indicar isso.
    return false;
  }

  String _mensagemAmigavelCartaoNaoAprovado({
    String? detalhe,
  }) {
    final detalheLimpo = detalhe?.trim() ?? '';

    // Não exibimos códigos internos nem "erro no servidor" para uma recusa
    // normal do emissor. Bancos nem sempre informam o motivo exato da recusa.
    if (detalheLimpo.isNotEmpty) {
      final texto = detalheLimpo.toLowerCase();

      if (texto.contains('limite') ||
          texto.contains('insufficient') ||
          texto.contains('insuficiente')) {
        return 'Pagamento não aprovado. Verifique se o cartão possui limite '
            'disponível suficiente ou tente outro cartão.';
      }

      if (texto.contains('bloqueado') || texto.contains('blocked')) {
        return 'Pagamento não aprovado. O cartão pode estar bloqueado para '
            'esta compra. Verifique com o banco emissor ou tente outro cartão.';
      }
    }

    return 'Pagamento não aprovado pelo cartão. Verifique o limite disponível, '
        'os dados informados ou tente outro cartão. Se o problema continuar, '
        'consulte o banco emissor.';
  }

  // ============================================================
  // PAGAMENTO COM CARTÃO
  // ============================================================

  Future<void> _processarPagamentoCartao() async {
    final email = _emailController.text.trim().toLowerCase();

    final cpf = _cpfTitularController.text.replaceAll(
      RegExp(r'\D'),
      '',
    );

    final nome = _nomeTitularController.text.trim();

    var telefone = _telefoneController.text.replaceAll(
      RegExp(r'\D'),
      '',
    );

    // A Efí utiliza DDD + número, sem o código internacional 55.
    if (telefone.startsWith('55') &&
        (telefone.length == 12 || telefone.length == 13)) {
      telefone = telefone.substring(2);
    }

    final valorEnvio = _valor ?? widget.valor ?? 0.0;

    // ----------------------------------------------------------
    // VALIDAÇÕES
    // ----------------------------------------------------------

    if (email.isEmpty || !email.contains('@')) {
      setState(() {
        _erro = 'Informe um e-mail válido para o recibo.';
      });
      return;
    }

    if (valorEnvio <= 0) {
      setState(() {
        _erro = 'O valor do pagamento deve ser maior que zero.';
      });
      return;
    }

    if (telefone.length != 10 && telefone.length != 11) {
      setState(() {
        _erro =
            'O telefone do seu perfil não foi encontrado ou está inválido. Informe um telefone com DDD.';
      });
      return;
    }

    final numero = _numeroCartaoController.text.replaceAll(
      RegExp(r'\D'),
      '',
    );

    final validade = _validadeController.text.trim();

    final cvv = _cvvController.text.trim();

    if (numero.length < 13 || numero.length > 16) {
      setState(() {
        _erro = 'Informe corretamente o número do cartão.';
      });
      return;
    }

    if (!_validarValidadeCartao(
      validade,
    )) {
      setState(() {
        _erro = 'A validade do cartão é inválida ou está vencida.';
      });
      return;
    }

    if (cvv.length < 3 || cvv.length > 4) {
      setState(() {
        _erro = 'Informe corretamente o CVV do cartão.';
      });
      return;
    }

    if (nome.isEmpty) {
      setState(() {
        _erro = 'Informe o nome impresso no cartão.';
      });
      return;
    }

    if (!_validarCPF(cpf)) {
      setState(() {
        _erro = 'CPF do titular inválido.';
      });
      return;
    }

    if (widget.ehRecorrente && (_planId == null || _planId!.trim().isEmpty)) {
      setState(() {
        _erro =
            'Este plano recorrente não possui um ID de plano Efí configurado.';
      });
      return;
    }

    _timerPollingCartao?.cancel();

    setState(() {
      _processandoCartao = true;
      _erro = null;
      _pagamentoAprovado = false;
      _pagamentoPendenteCartao = false;
      _mensagemPagamentoPendente = null;
    });

    final inicioTentativa = DateTime.now();

    try {
      final user = Supabase.instance.client.auth.currentUser;

      if (user == null) {
        throw 'Usuário não autenticado.';
      }

      final session = Supabase.instance.client.auth.currentSession;

      if (session == null || session.accessToken.trim().isEmpty) {
        throw 'Sua sessão expirou. Entre novamente para continuar.';
      }

      // --------------------------------------------------------
      // 1. DEFINE SE É PRIMEIRA ASSINATURA OU TROCA DE PLANO
      // --------------------------------------------------------
      //
      // Para pagamento avulso esta consulta não é executada.
      //
      // Para recorrente:
      // - sem assinatura atual  -> /cobrar-assinatura
      // - com assinatura atual  -> /trocar-assinatura
      // --------------------------------------------------------

      bool trocarPlanoRecorrente = false;

      if (widget.ehRecorrente) {
        trocarPlanoRecorrente = await _possuiAssinaturaRecorrenteAtual(
          user.id,
        );
      }

      // --------------------------------------------------------
      // 2. TOKENIZA O CARTÃO NA EFÍ
      // --------------------------------------------------------

      final paymentToken = await _obterPaymentToken();

      if (paymentToken == null || paymentToken.isEmpty) {
        throw 'Não foi possível gerar o token do cartão.';
      }

      // --------------------------------------------------------
      // 3. DEFINE ENDPOINT
      // --------------------------------------------------------

      final String endpoint;

      if (!widget.ehRecorrente) {
        endpoint = '$_backendUrl/cobrar-cartao';
      } else if (trocarPlanoRecorrente) {
        endpoint = '$_backendUrl/trocar-assinatura';
      } else {
        endpoint = '$_backendUrl/cobrar-assinatura';
      }

      // --------------------------------------------------------
      // 4. MONTA PAYLOAD PARA O ENDPOINT CORRETO
      // --------------------------------------------------------
      //
      // ATENÇÃO:
      //
      // /cobrar-assinatura espera:
      //   plan_id = efi_plan_id
      //
      // /trocar-assinatura espera:
      //   plano_id = UUID do plano em tab_planos
      //
      // O backend da troca consulta valor_recorrente e efi_plan_id
      // diretamente no Supabase, evitando confiar em preço vindo
      // do aplicativo.
      // --------------------------------------------------------

      final payloadBackend = <String, dynamic>{
        'usuario_id': user.id,
        'valor': valorEnvio,
        'email': email,
        'nome': nome,
        'cpf': cpf,
        'telefone': telefone,
        'descricao': widget.descricao ?? 'Pagamento Ache Obra',
        'origem_tipo': widget.origemTipo,
        'origem_id': widget.origemId,
        'eh_recorrente': widget.ehRecorrente,
        'payment_token': paymentToken,
        'parcelas': 1,
        if (widget.ehRecorrente && trocarPlanoRecorrente)
          'plano_id': widget.origemId
        else if (widget.ehRecorrente && _planId != null)
          'plan_id': _planId,
      };

      debugPrint(
        'Enviando pagamento para: $endpoint',
      );

      if (widget.ehRecorrente) {
        debugPrint(
          trocarPlanoRecorrente
              ? 'Fluxo recorrente: TROCA IMEDIATA DE PLANO.'
              : 'Fluxo recorrente: PRIMEIRA ASSINATURA.',
        );
      }

      // --------------------------------------------------------
      // 5. ENVIA PARA O RENDER
      // --------------------------------------------------------
      //
      // O timeout foi ampliado para 90 segundos porque o backend,
      // após receber a resposta da Efí, registra o pagamento no
      // Supabase antes de responder ao app.
      // --------------------------------------------------------

      http.Response response;

      try {
        response = await http
            .post(
              Uri.parse(endpoint),
              headers: {
                'Content-Type': 'application/json',
                'Authorization': 'Bearer ${session.accessToken}',
              },
              body: jsonEncode(
                payloadBackend,
              ),
            )
            .timeout(
              const Duration(
                seconds: 90,
              ),
            );
      } on TimeoutException catch (e) {
        _registrarErroTecnico(
          'TIMEOUT NO BACKEND DO CARTÃO',
          e,
          detalhe: 'Endpoint: $endpoint | timeout=90s',
        );

        debugPrint(
          'Timeout ao aguardar resposta do backend após 90 segundos.',
        );

        // ------------------------------------------------------
        // RECUPERAÇÃO DE SEGURANÇA PARA PAGAMENTO AVULSO
        // ------------------------------------------------------
        //
        // A cobrança pode ter sido aprovada na Efí mesmo que a
        // resposta HTTP tenha estourado o timeout. Antes de mostrar
        // erro, procuramos o pagamento recém-gravado no Supabase.
        // ------------------------------------------------------

        if (!widget.ehRecorrente) {
          final pagamentoRecuperado = await _recuperarPagamentoAvulsoAprovado(
            usuarioId: user.id,
            inicioTentativa: inicioTentativa,
          );

          if (pagamentoRecuperado != null) {
            if (mounted) {
              setState(() {
                _erro = null;
                _pagamentoAprovado = true;
              });
            }

            debugPrint(
              'Pagamento considerado aprovado após recuperação '
              'do registro no Supabase.',
            );

            return;
          }

          throw 'O pagamento está demorando mais que o esperado para ser confirmado. '
              'Não tente pagar novamente agora para evitar cobrança duplicada. '
              'Aguarde alguns minutos e verifique seu plano.';
        }

        throw trocarPlanoRecorrente
            ? 'A troca de plano está demorando mais que o esperado para ser confirmada. '
                'Não tente trocar novamente agora. Aguarde alguns minutos e verifique seu plano.'
            : 'A assinatura está demorando mais que o esperado para ser confirmada. '
                'Aguarde alguns minutos antes de tentar novamente.';
      }

      debugPrint(
        'Resposta Render: ${response.statusCode}',
      );

      // --------------------------------------------------------
      // 5. PROCESSAR RESPOSTA
      // --------------------------------------------------------

      Map<String, dynamic> data = {};

      try {
        final decoded = jsonDecode(
          response.body,
        );

        if (decoded is Map) {
          data = Map<String, dynamic>.from(
            decoded,
          );
        }
      } catch (e) {
        _registrarErroTecnico(
          'RESPOSTA INVÁLIDA DO BACKEND DO CARTÃO',
          e,
          detalhe: 'HTTP ${response.statusCode} | endpoint=$endpoint',
        );
        throw 'Resposta inválida recebida do servidor.';
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        final erroServidor = data['error'] ??
            data['error_description'] ??
            data['message'] ??
            'Erro desconhecido';

        final statusErro =
            data['status']?.toString().trim().toLowerCase() ?? '';

        final recusaNormal = _ehRecusaNormalDeCartao(
          httpStatus: response.statusCode,
          status: statusErro,
          mensagem: erroServidor.toString(),
        );

        if (recusaNormal) {
          // Recusa do cartão é uma resposta de negócio esperada.
          // Não deve aparecer como "erro no servidor" e não deve gerar
          // alerta técnico no Discord. O plano atual permanece inalterado.
          throw _mensagemAmigavelCartaoNaoAprovado(
            detalhe: erroServidor.toString(),
          );
        }

        if (response.statusCode >= 500) {
          _registrarErroTecnico(
            'FALHA INTERNA DO BACKEND DO CARTÃO',
            'HTTP ${response.statusCode}',
            detalhe: 'endpoint=$endpoint | erro=$erroServidor',
          );

          throw 'Não foi possível concluir o pagamento neste momento. '
              'Tente novamente em alguns instantes.';
        }

        // Erros 4xx que não representam recusa bancária podem ser regras
        // de negócio/validação do backend. Mantemos a mensagem recebida,
        // sem rotulá-la como falha interna do servidor.
        throw erroServidor.toString();
      }

      if (data['error'] != null) {
        throw data['error'].toString();
      }

      // --------------------------------------------------------
      // 6. STATUS
      // --------------------------------------------------------

      final dynamic dadosInternos = data['data'];

      String status = '';

      if (data['status'] != null) {
        status = data['status'].toString().toLowerCase();
      } else if (dadosInternos is Map && dadosInternos['status'] != null) {
        status = dadosInternos['status'].toString().toLowerCase();
      }

      // --------------------------------------------------------
      // CONFIRMAÇÃO REAL DO PAGAMENTO
      // --------------------------------------------------------
      //
      // NÃO usamos mais data['pago'] isoladamente para cartão porque
      // versões anteriores do backend marcavam pago=true quando a Efí
      // devolvia apenas "approved".
      //
      // Avulso:
      //   somente status paid/settled/pago libera o plano.
      //
      // Recorrente:
      //   "active" é apenas o estado da assinatura.
      //   A primeira cobrança precisa estar paid/settled.
      // --------------------------------------------------------

      final statusPrimeiraCobranca = widget.ehRecorrente
          ? _extrairStatusPrimeiraCobrancaRecorrente(
              data,
            )
          : '';

      final bool pagamentoConfirmado;

      if (widget.ehRecorrente) {
        pagamentoConfirmado = data['pagamento_confirmado'] == true ||
            _statusCartaoDefinitivamentePago(
              statusPrimeiraCobranca,
            );
      } else {
        pagamentoConfirmado = data['pagamento_confirmado'] == true ||
            _statusCartaoDefinitivamentePago(
              status,
            );
      }

      debugPrint(
        'Confirmação cartão: '
        'recorrente=${widget.ehRecorrente} '
        '| status=$status '
        '| status_primeira_cobranca=${statusPrimeiraCobranca.isEmpty ? '-' : statusPrimeiraCobranca} '
        '| confirmado=$pagamentoConfirmado',
      );

      if (!pagamentoConfirmado) {
        String motivoRecusa = '';

        dynamic refusal;

        if (dadosInternos is Map) {
          refusal = dadosInternos['refusal'];
        }

        refusal ??= data['refusal'];

        if (refusal is Map && refusal['reason'] != null) {
          motivoRecusa = refusal['reason'].toString().trim();
        }

        if (motivoRecusa.isEmpty && data['reason'] != null) {
          motivoRecusa = data['reason'].toString().trim();
        }

        if (motivoRecusa.isNotEmpty) {
          throw _mensagemAmigavelCartaoNaoAprovado(
            detalhe: motivoRecusa,
          );
        }

        final statusAnalise = widget.ehRecorrente
            ? (statusPrimeiraCobranca.isNotEmpty
                ? statusPrimeiraCobranca
                : status)
            : status;

        final statusPendente = statusAnalise == 'approved' ||
            statusAnalise == 'authorized' ||
            statusAnalise == 'active' ||
            statusAnalise == 'waiting' ||
            statusAnalise == 'pending' ||
            statusAnalise == 'new' ||
            statusAnalise == 'aguardando' ||
            statusAnalise.isEmpty;

        if (statusPendente) {
          if (mounted) {
            setState(() {
              _erro = null;
              _pagamentoAprovado = false;
              _pagamentoPendenteCartao = true;
              _mensagemPagamentoPendente = widget.ehRecorrente
                  ? 'A assinatura foi criada, mas a Efí ainda não confirmou '
                      'o pagamento da primeira cobrança.\n\n'
                      'Seu plano só será alterado depois da confirmação real do pagamento.'
                  : 'A cobrança foi criada, mas a Efí ainda não confirmou '
                      'o pagamento.\n\n'
                      'Seu plano não será alterado enquanto o pagamento estiver pendente.';
            });
          }

          if (widget.ehRecorrente) {
            _iniciarPollingCartaoRecorrente(
              user.id,
            );
          }

          return;
        }

        final statusRecusado = _ehRecusaNormalDeCartao(
          httpStatus: response.statusCode,
          status: statusAnalise,
          mensagem: motivoRecusa,
        );

        if (statusRecusado) {
          throw _mensagemAmigavelCartaoNaoAprovado(
            detalhe: motivoRecusa,
          );
        }

        throw 'Pagamento não aprovado. Tente novamente ou utilize outro cartão.';
      }

      // --------------------------------------------------------
      // 7. CONFIRMA REGISTRO DO PAGAMENTO AVULSO
      // --------------------------------------------------------
      //
      // O backend novo devolve pagamento_avulso_id quando consegue
      // salvar a compra em tab_pagamentos_avulsos. Isso é importante
      // para o cancelamento/estorno posterior em até 7 dias.
      // --------------------------------------------------------

      if (!widget.ehRecorrente) {
        final pagamentoAvulsoId =
            data['pagamento_avulso_id']?.toString().trim();

        final registroPagamentoSalvo = data['registro_pagamento_salvo'] == true;

        debugPrint(
          'Pagamento avulso aprovado. '
          'pagamento_avulso_id=${pagamentoAvulsoId ?? '-'} '
          '| registro_salvo=$registroPagamentoSalvo',
        );

        // Se a Efí aprovou mas o backend não conseguiu salvar o registro,
        // tentamos localizar o pagamento por segurança antes de concluir.
        if (!registroPagamentoSalvo ||
            pagamentoAvulsoId == null ||
            pagamentoAvulsoId.isEmpty) {
          final pagamentoRecuperado = await _recuperarPagamentoAvulsoAprovado(
            usuarioId: user.id,
            inicioTentativa: inicioTentativa,
          );

          if (pagamentoRecuperado == null) {
            _registrarErroTecnico(
              'PAGAMENTO APROVADO MAS NÃO REGISTRADO',
              'A Efí aprovou a cobrança, porém o registro local não foi confirmado.',
              detalhe: 'Pagamento avulso com cartão.',
            );

            throw 'O pagamento foi aprovado pela Efí, mas o sistema ainda não conseguiu '
                'registrar a compra para controle de cancelamento. '
                'Não efetue um novo pagamento. Entre em contato com o suporte.';
          }
        }
      }

      // --------------------------------------------------------
      // 8. SUCESSO
      // --------------------------------------------------------

      if (mounted) {
        setState(() {
          _erro = null;
          _pagamentoAprovado = true;
        });
      }
    } catch (e) {
      debugPrint(
        'Erro no pagamento com cartão: $e',
      );

      if (mounted) {
        setState(() {
          _erro = e.toString().replaceFirst(
                'Exception: ',
                '',
              );
        });
      }
    } finally {
      if (mounted) {
        setState(() {
          _processandoCartao = false;
        });
      }
    }
  }

  // ============================================================
  // COPIAR PIX
  // ============================================================

  void _copiarCodigo() {
    final codigo = _qrCodeCopiaECola;

    if (codigo == null || codigo.trim().isEmpty) {
      return;
    }

    Clipboard.setData(
      ClipboardData(
        text: codigo,
      ),
    );

    ScaffoldMessenger.of(context).showSnackBar(
      const SnackBar(
        content: Text(
          'Código Pix copiado com sucesso!',
        ),
        backgroundColor: Colors.green,
      ),
    );
  }

  // ============================================================
  // CONTEÚDO PIX
  // ============================================================

  List<Widget> _buildConteudoPix() {
    if (_qrCodeCopiaECola != null) {
      return [
        Container(
          padding: const EdgeInsets.all(12),
          decoration: BoxDecoration(
            color: Colors.white,
            borderRadius: BorderRadius.circular(
              12,
            ),
          ),
          child: Image.network(
            'https://api.qrserver.com/v1/create-qr-code/?size=250x250&data=${Uri.encodeComponent(_qrCodeCopiaECola!)}',
            width: 170,
            height: 170,
            fit: BoxFit.cover,
            loadingBuilder: (
              context,
              child,
              loadingProgress,
            ) {
              if (loadingProgress == null) {
                return child;
              }

              return const SizedBox(
                width: 170,
                height: 170,
                child: Center(
                  child: CircularProgressIndicator(
                    color: Color(
                      0xFFFF8C00,
                    ),
                  ),
                ),
              );
            },
            errorBuilder: (
              _,
              __,
              ___,
            ) {
              return const Icon(
                Icons.qr_code,
                size: 100,
                color: Colors.black,
              );
            },
          ),
        ),
        const SizedBox(
          height: 16,
        ),
        const Text(
          'Escaneie o QR Code ou copie o código abaixo para pagar no seu banco:',
          textAlign: TextAlign.center,
          style: TextStyle(
            color: Colors.white70,
            fontSize: 12,
          ),
        ),
        const SizedBox(
          height: 12,
        ),
        const Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 14,
              height: 14,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: Color(0xFFFF8C00),
              ),
            ),
            SizedBox(
              width: 8,
            ),
            Text(
              'Aguardando pagamento...',
              style: TextStyle(
                color: Colors.white54,
                fontSize: 11,
              ),
            ),
          ],
        ),
        const SizedBox(
          height: 16,
        ),
        ElevatedButton.icon(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(
              0xFFFF8C00,
            ),
            padding: const EdgeInsets.symmetric(
              horizontal: 20,
              vertical: 12,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(
                8,
              ),
            ),
          ),
          onPressed: _copiarCodigo,
          icon: const Icon(
            Icons.copy,
            color: Colors.white,
            size: 18,
          ),
          label: const Text(
            'COPIAR CÓDIGO PIX',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      ];
    }

    return [
      TextField(
        controller: _cpfController,
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(
            11,
          ),
        ],
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
        ),
        decoration: const InputDecoration(
          labelText: 'CPF do Pagador (obrigatório)',
          labelStyle: TextStyle(
            color: Colors.white54,
            fontSize: 12,
          ),
          filled: true,
          fillColor: Color(0xFF1A2C42),
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(
        height: 10,
      ),
      TextField(
        controller: _emailController,
        keyboardType: TextInputType.emailAddress,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
        ),
        decoration: const InputDecoration(
          labelText: 'E-mail para comprovante',
          labelStyle: TextStyle(
            color: Colors.white54,
            fontSize: 12,
          ),
          filled: true,
          fillColor: Color(0xFF1A2C42),
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(
        height: 12,
      ),
      const Text(
        'Pagamento processado pelo backend seguro do Ache Obra.',
        textAlign: TextAlign.center,
        style: TextStyle(
          color: Colors.white30,
          fontSize: 10,
        ),
      ),
      const SizedBox(
        height: 8,
      ),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(
              0xFFFF8C00,
            ),
            padding: const EdgeInsets.symmetric(
              vertical: 14,
            ),
          ),
          onPressed: _carregando ? null : _processarPagamentoPix,
          child: _carregando
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              : const Text(
                  'GERAR PIX DE PAGAMENTO',
                  style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
        ),
      ),
    ];
  }

  // ============================================================
  // CONTEÚDO CARTÃO
  // ============================================================

  List<Widget> _buildConteudoCartao() {
    return [
      TextField(
        controller: _emailController,
        keyboardType: TextInputType.emailAddress,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
        ),
        decoration: const InputDecoration(
          labelText: 'E-mail do Pagador (para recibo)',
          labelStyle: TextStyle(
            color: Colors.white54,
            fontSize: 12,
          ),
          filled: true,
          fillColor: Color(0xFF1A2C42),
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(
        height: 10,
      ),
      TextField(
        controller: _telefoneController,
        keyboardType: TextInputType.phone,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(13),
        ],
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
        ),
        decoration: const InputDecoration(
          labelText: 'Telefone do Titular com DDD',
          hintText: 'Carregado automaticamente do seu perfil',
          hintStyle: TextStyle(
            color: Colors.white30,
            fontSize: 12,
          ),
          labelStyle: TextStyle(
            color: Colors.white54,
            fontSize: 12,
          ),
          filled: true,
          fillColor: Color(0xFF1A2C42),
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(
        height: 10,
      ),
      TextField(
        controller: _numeroCartaoController,
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          NumeroCartaoFormatter(),
        ],
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
        ),
        decoration: const InputDecoration(
          labelText: 'Número do Cartão',
          labelStyle: TextStyle(
            color: Colors.white54,
            fontSize: 12,
          ),
          filled: true,
          fillColor: Color(0xFF1A2C42),
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(
        height: 10,
      ),
      Row(
        children: [
          Expanded(
            child: TextField(
              controller: _validadeController,
              keyboardType: TextInputType.number,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                ValidadeCartaoFormatter(),
              ],
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
              ),
              decoration: const InputDecoration(
                labelText: 'Validade (MM/AA)',
                labelStyle: TextStyle(
                  color: Colors.white54,
                  fontSize: 12,
                ),
                filled: true,
                fillColor: Color(0xFF1A2C42),
                border: OutlineInputBorder(),
              ),
            ),
          ),
          const SizedBox(
            width: 10,
          ),
          Expanded(
            child: TextField(
              controller: _cvvController,
              keyboardType: TextInputType.number,
              obscureText: true,
              inputFormatters: [
                FilteringTextInputFormatter.digitsOnly,
                LengthLimitingTextInputFormatter(
                  4,
                ),
              ],
              style: const TextStyle(
                color: Colors.white,
                fontSize: 13,
              ),
              decoration: const InputDecoration(
                labelText: 'CVV',
                labelStyle: TextStyle(
                  color: Colors.white54,
                  fontSize: 12,
                ),
                filled: true,
                fillColor: Color(0xFF1A2C42),
                border: OutlineInputBorder(),
              ),
            ),
          ),
        ],
      ),
      const SizedBox(
        height: 10,
      ),
      TextField(
        controller: _nomeTitularController,
        textCapitalization: TextCapitalization.words,
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
        ),
        decoration: const InputDecoration(
          labelText: 'Nome impresso no cartão',
          labelStyle: TextStyle(
            color: Colors.white54,
            fontSize: 12,
          ),
          filled: true,
          fillColor: Color(0xFF1A2C42),
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(
        height: 10,
      ),
      TextField(
        controller: _cpfTitularController,
        keyboardType: TextInputType.number,
        inputFormatters: [
          FilteringTextInputFormatter.digitsOnly,
          LengthLimitingTextInputFormatter(
            11,
          ),
        ],
        style: const TextStyle(
          color: Colors.white,
          fontSize: 13,
        ),
        decoration: const InputDecoration(
          labelText: 'CPF do Titular',
          labelStyle: TextStyle(
            color: Colors.white54,
            fontSize: 12,
          ),
          filled: true,
          fillColor: Color(0xFF1A2C42),
          border: OutlineInputBorder(),
        ),
      ),
      const SizedBox(
        height: 12,
      ),
      Container(
        padding: const EdgeInsets.all(10),
        decoration: BoxDecoration(
          color: Colors.green.withValues(
            alpha: 0.08,
          ),
          borderRadius: BorderRadius.circular(
            8,
          ),
          border: Border.all(
            color: Colors.green.withValues(
              alpha: 0.25,
            ),
          ),
        ),
        child: const Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(
              Icons.lock_outline,
              color: Colors.greenAccent,
              size: 17,
            ),
            SizedBox(
              width: 8,
            ),
            Expanded(
              child: Text(
                'Os dados do cartão são tokenizados pela Efí. O número completo e o CVV não são enviados ao servidor do Ache Obra.',
                style: TextStyle(
                  color: Colors.white60,
                  fontSize: 11,
                  height: 1.3,
                ),
              ),
            ),
          ],
        ),
      ),
      const SizedBox(
        height: 20,
      ),
      SizedBox(
        width: double.infinity,
        child: ElevatedButton(
          style: ElevatedButton.styleFrom(
            backgroundColor: const Color(
              0xFFFF8C00,
            ),
            padding: const EdgeInsets.symmetric(
              vertical: 14,
            ),
          ),
          onPressed: _processandoCartao ? null : _processarPagamentoCartao,
          child: _processandoCartao
              ? const SizedBox(
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                    color: Colors.white,
                    strokeWidth: 2,
                  ),
                )
              : Text(
                  widget.ehRecorrente
                      ? 'ASSINAR COM CARTÃO'
                      : 'PAGAR COM CARTÃO',
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                  ),
                ),
        ),
      ),
    ];
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(
    BuildContext context,
  ) {
    final double valorExibido = _valor ?? widget.valor ?? 0.0;

    final mediaQuery = MediaQuery.of(context);

    final double alturaDisponivel = mediaQuery.size.height -
        mediaQuery.viewInsets.bottom -
        mediaQuery.padding.top -
        32;

    return Dialog(
      insetPadding: const EdgeInsets.symmetric(
        horizontal: 16,
        vertical: 16,
      ),
      backgroundColor: const Color(0xFF101B2B),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(
          16,
        ),
      ),
      child: ConstrainedBox(
        constraints: BoxConstraints(
          maxHeight: alturaDisponivel > 200 ? alturaDisponivel : 200,
        ),
        child: SingleChildScrollView(
          keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
          child: Padding(
            padding: const EdgeInsets.all(
              24,
            ),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisAlignment: MainAxisAlignment.spaceBetween,
                  children: [
                    const Text(
                      'Finalizar Pagamento',
                      style: TextStyle(
                        color: Colors.white,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    IconButton(
                      icon: const Icon(
                        Icons.close,
                        color: Colors.white54,
                      ),
                      onPressed: () {
                        Navigator.of(
                          context,
                        ).pop(
                          _pagamentoAprovado,
                        );
                      },
                    ),
                  ],
                ),
                const Divider(
                  color: Colors.white12,
                ),
                const SizedBox(
                  height: 12,
                ),

                // ABAS
                if (!widget.ehRecorrente && !_temMetodoPagamentoFixo) ...[
                  Row(
                    children: [
                      _buildAbaMetodo(
                        'PIX',
                        'pix',
                        Icons.pix,
                      ),
                      const SizedBox(
                        width: 8,
                      ),
                      _buildAbaMetodo(
                        'Cartão',
                        'cartao',
                        Icons.credit_card,
                      ),
                    ],
                  ),
                  const SizedBox(
                    height: 20,
                  ),
                ],

                // CABEÇALHO CARTÃO
                if (_metodoSelecionado == 'cartao') ...[
                  Container(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
                    decoration: BoxDecoration(
                      color: const Color(
                        0xFFFF8C00,
                      ).withValues(
                        alpha: 0.15,
                      ),
                      borderRadius: BorderRadius.circular(
                        8,
                      ),
                      border: Border.all(
                        color: const Color(
                          0xFFFF8C00,
                        ).withValues(
                          alpha: 0.3,
                        ),
                      ),
                    ),
                    child: const Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.credit_card,
                          color: Color(
                            0xFFFF8C00,
                          ),
                          size: 18,
                        ),
                        SizedBox(
                          width: 8,
                        ),
                        Text(
                          'CARTÃO DE CRÉDITO',
                          style: TextStyle(
                            color: Color(
                              0xFFFF8C00,
                            ),
                            fontSize: 12,
                            fontWeight: FontWeight.bold,
                            letterSpacing: 0.8,
                          ),
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(
                    height: 14,
                  ),
                ],

                // CARREGANDO DADOS
                if (_carregandoDados) ...[
                  const Padding(
                    padding: EdgeInsets.symmetric(
                      vertical: 30,
                    ),
                    child: CircularProgressIndicator(
                      color: Color(
                        0xFFFF8C00,
                      ),
                    ),
                  ),
                  const SizedBox(
                    height: 12,
                  ),
                  const Text(
                    'Carregando informações...',
                    style: TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                    ),
                  ),
                ] else ...[
                  // VALOR
                  if (valorExibido > 0) ...[
                    Text(
                      '${widget.ehRecorrente ? 'Valor Mensal' : 'Valor Total'}: R\$ ${valorExibido.toStringAsFixed(2).replaceAll('.', ',')}',
                      style: const TextStyle(
                        color: Color(
                          0xFFFF8C00,
                        ),
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(
                      height: 16,
                    ),
                  ],

                  // PROCESSANDO
                  if (_carregando) ...[
                    const CircularProgressIndicator(
                      color: Color(
                        0xFFFF8C00,
                      ),
                    ),
                    const SizedBox(
                      height: 16,
                    ),
                    const Text(
                      'Gerando cobrança na Efí...',
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                    ),
                  ]

                  // PAGAMENTO COM CARTÃO AINDA PENDENTE
                  else if (_pagamentoPendenteCartao) ...[
                    const Icon(
                      Icons.schedule,
                      color: Color(
                        0xFFFFB74D,
                      ),
                      size: 52,
                    ),
                    const SizedBox(
                      height: 12,
                    ),
                    const Text(
                      'Pagamento em processamento',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Color(
                          0xFFFFB74D,
                        ),
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(
                      height: 10,
                    ),
                    Text(
                      _mensagemPagamentoPendente ??
                          'Aguardando confirmação definitiva da Efí.',
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                    ),
                    if (widget.ehRecorrente) ...[
                      const SizedBox(
                        height: 16,
                      ),
                      const SizedBox(
                        width: 22,
                        height: 22,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Color(
                            0xFFFF8C00,
                          ),
                        ),
                      ),
                      const SizedBox(
                        height: 8,
                      ),
                      const Text(
                        'Verificando a confirmação do pagamento...',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          color: Colors.white54,
                          fontSize: 11,
                        ),
                      ),
                    ],
                    const SizedBox(
                      height: 20,
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(
                          0xFFFF8C00,
                        ),
                      ),
                      onPressed: () {
                        _timerPollingCartao?.cancel();

                        Navigator.of(
                          context,
                        ).pop(false);
                      },
                      child: const Text(
                        'OK',
                        style: TextStyle(
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ]

                  // ERRO
                  else if (_erro != null) ...[
                    const Icon(
                      Icons.error_outline,
                      color: Colors.redAccent,
                      size: 48,
                    ),
                    const SizedBox(
                      height: 12,
                    ),
                    Text(
                      _erro!,
                      textAlign: TextAlign.center,
                      style: const TextStyle(
                        color: Colors.redAccent,
                        fontSize: 13,
                      ),
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
                      onPressed: () {
                        setState(() {
                          _erro = null;
                        });
                      },
                      child: const Text(
                        'Tentar Novamente',
                        style: TextStyle(
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ]

                  // SUCESSO
                  else if (_pagamentoAprovado) ...[
                    const Icon(
                      Icons.check_circle_outline,
                      color: Colors.greenAccent,
                      size: 56,
                    ),
                    const SizedBox(
                      height: 12,
                    ),
                    const Text(
                      'Pagamento Aprovado!',
                      style: TextStyle(
                        color: Colors.greenAccent,
                        fontSize: 18,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    const SizedBox(
                      height: 8,
                    ),
                    const Text(
                      'Seu pagamento foi confirmado com sucesso.\n\n'
                      'Toque em OK para continuar e ativar o novo plano.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white70,
                        fontSize: 13,
                      ),
                    ),
                    const SizedBox(
                      height: 20,
                    ),
                    ElevatedButton(
                      style: ElevatedButton.styleFrom(
                        backgroundColor: const Color(
                          0xFFFF8C00,
                        ),
                      ),
                      onPressed: () {
                        Navigator.of(
                          context,
                        ).pop(true);
                      },
                      child: const Text(
                        'OK',
                        style: TextStyle(
                          color: Colors.white,
                        ),
                      ),
                    ),
                  ]

                  // CONTEÚDO
                  else ...[
                    if (_metodoSelecionado == 'pix')
                      ..._buildConteudoPix()
                    else if (_metodoSelecionado == 'cartao')
                      ..._buildConteudoCartao(),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  // ============================================================
  // ABA PIX / CARTÃO
  // ============================================================

  Widget _buildAbaMetodo(
    String label,
    String chave,
    IconData icone,
  ) {
    final selecionado = _metodoSelecionado == chave;

    return Expanded(
      child: InkWell(
        onTap: () {
          _timerPollingPix?.cancel();
          _timerPollingCartao?.cancel();

          setState(() {
            _metodoSelecionado = chave;
            _erro = null;
            _pagamentoAprovado = false;
            _pagamentoPendenteCartao = false;
            _mensagemPagamentoPendente = null;
            _carregando = false;
            _processandoCartao = false;
          });
        },
        borderRadius: BorderRadius.circular(
          8,
        ),
        child: Container(
          padding: const EdgeInsets.symmetric(
            vertical: 10,
          ),
          decoration: BoxDecoration(
            color: selecionado
                ? const Color(
                    0xFFFF8C00,
                  ).withValues(
                    alpha: 0.2,
                  )
                : const Color(
                    0xFF1A2C42,
                  ),
            borderRadius: BorderRadius.circular(
              8,
            ),
            border: Border.all(
              color: selecionado
                  ? const Color(
                      0xFFFF8C00,
                    )
                  : Colors.white12,
            ),
          ),
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icone,
                size: 16,
                color: selecionado
                    ? const Color(
                        0xFFFF8C00,
                      )
                    : Colors.white54,
              ),
              const SizedBox(
                width: 6,
              ),
              Text(
                label,
                style: TextStyle(
                  color: selecionado ? Colors.white : Colors.white54,
                  fontWeight: FontWeight.bold,
                  fontSize: 12,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

///
/// WEBVIEW DE TOKENIZAÇÃO EFÍ
///
class EfiTokenizacaoPage extends StatefulWidget {
  final void Function(String etapa, Object erro, String? detalhe)?
      onErroTecnico;

  final String identificadorConta;
  final String ambiente;
  final String bandeira;
  final String numero;
  final String cvv;
  final String mes;
  final String ano;
  final String nomeTitular;
  final String cpfTitular;

  const EfiTokenizacaoPage({
    super.key,
    required this.identificadorConta,
    required this.ambiente,
    required this.bandeira,
    required this.numero,
    required this.cvv,
    required this.mes,
    required this.ano,
    required this.nomeTitular,
    required this.cpfTitular,
    this.onErroTecnico,
  });

  @override
  State<EfiTokenizacaoPage> createState() => _EfiTokenizacaoPageState();
}

class _EfiTokenizacaoPageState extends State<EfiTokenizacaoPage> {
  late final WebViewController _controller;

  bool _carregando = true;
  bool _iniciado = false;
  bool _finalizando = false;

  @override
  void initState() {
    super.initState();

    _controller = WebViewController()
      ..setJavaScriptMode(
        JavaScriptMode.unrestricted,
      )
      ..setBackgroundColor(
        const Color(
          0xFF101B2B,
        ),
      )
      ..addJavaScriptChannel(
        'EfiToken',
        onMessageReceived: _receberToken,
      )
      ..addJavaScriptChannel(
        'EfiErro',
        onMessageReceived: _receberErro,
      )
      ..setNavigationDelegate(
        NavigationDelegate(
          onPageFinished: _paginaCarregada,
          onWebResourceError: (error) {
            if (!mounted || _finalizando) {
              return;
            }

            widget.onErroTecnico?.call(
              'FALHA AO CARREGAR WEBVIEW DE TOKENIZAÇÃO EFÍ',
              'WebResourceError code=${error.errorCode}',
              error.description,
            );

            setState(() {
              _carregando = false;
            });

            _mostrarErro(
              'Não foi possível carregar o serviço de tokenização da Efí.',
            );
          },
        ),
      )
      ..loadHtmlString(
        _htmlTokenizacao(),
        baseUrl: widget.ambiente == 'production'
            ? 'https://cobrancas.api.efipay.com.br/'
            : 'https://cobrancas-h.api.efipay.com.br/',
      );
  }

  // ============================================================
  // HTML DA TOKENIZAÇÃO
  // ============================================================

  String _htmlTokenizacao() {
    final identificador = jsonEncode(
      widget.identificadorConta,
    );

    final ambiente = jsonEncode(
      widget.ambiente,
    );

    final bandeira = jsonEncode(
      widget.bandeira,
    );

    final numero = jsonEncode(
      widget.numero,
    );

    final cvv = jsonEncode(
      widget.cvv,
    );

    final mes = jsonEncode(
      widget.mes,
    );

    final ano = jsonEncode(
      widget.ano,
    );

    final nome = jsonEncode(
      widget.nomeTitular,
    );

    final cpf = jsonEncode(
      widget.cpfTitular,
    );

    return '''
<!DOCTYPE html>
<html lang="pt-BR">

<head>

<meta charset="UTF-8">

<meta
  name="viewport"
  content="width=device-width, initial-scale=1.0"
/>

<title>Tokenização Efí</title>

<script
  src="https://cdn.jsdelivr.net/npm/payment-token-efi/dist/payment-token-efi-umd.min.js">
</script>

<style>

html,
body {

  margin: 0;

  padding: 0;

  background: #101B2B;

  color: white;

  font-family: Arial, sans-serif;

  height: 100%;

}

body {

  display: flex;

  align-items: center;

  justify-content: center;

}

.container {

  text-align: center;

  padding: 24px;

}

.titulo {

  font-size: 17px;

  font-weight: bold;

  margin-bottom: 10px;

}

.texto {

  font-size: 13px;

  color: #BFC5CC;

}

.spinner {

  width: 30px;

  height: 30px;

  border: 3px solid rgba(255,255,255,0.15);

  border-top-color: #FF8C00;

  border-radius: 50%;

  animation: spin 0.8s linear infinite;

  margin: 0 auto 16px auto;

}

@keyframes spin {

  from {

    transform: rotate(0deg);

  }

  to {

    transform: rotate(360deg);

  }

}

</style>

</head>

<body>

<div class="container">

  <div class="spinner"></div>

  <div class="titulo">
    Protegendo os dados do cartão
  </div>

  <div class="texto">
    Aguardarde enquanto a Efí processa os dados com segurança.
  </div>

</div>

<script>

let tokenizacaoIniciada = false;

function enviarErro(mensagem) {

  try {

    EfiErro.postMessage(
      String(
        mensagem ||
        'Erro desconhecido'
      )
    );

  } catch (e) {

    console.log(e);

  }

}

async function tokenizarCartao() {

  if (tokenizacaoIniciada) {

    return;

  }

  tokenizacaoIniciada = true;

  try {

    if (
      typeof EfiPay === 'undefined' ||
      !EfiPay.CreditCard
    ) {

      throw new Error(
        'A biblioteca de tokenização da Efí não foi carregada.'
      );

    }

    try {
      EfiPay.CreditCard.debugger(true);
    } catch (_) {}

    const bloqueado = await EfiPay.CreditCard.isScriptBlocked();
    if (bloqueado === true) {
      throw new Error('O script de segurança da Efí está bloqueado neste WebView.');
    }

    // A própria biblioteca oficial da Efí identifica a bandeira.
    // Isso evita classificar cartões Elo iniciados por 4 como Visa e também
    // acompanha novos BINs sem depender de regex fixa no aplicativo.
    const bandeiraDetectada =
      await EfiPay.CreditCard
        .setCardNumber(
          $numero
        )
        .verifyCardBrand();

    const bandeiraNormalizada =
      String(bandeiraDetectada || '')
        .trim()
        .toLowerCase();

    if (
      !bandeiraNormalizada ||
      bandeiraNormalizada === 'undefined' ||
      bandeiraNormalizada === 'unsupported'
    ) {
      throw new Error(
        'A bandeira deste cartão não é suportada pela Efí.'
      );
    }

    const resultado =
      await EfiPay.CreditCard

        .setAccount(
          $identificador
        )

        .setEnvironment(
          $ambiente
        )

        .setCreditCardData({

          brand:
            bandeiraNormalizada,

          number:
            $numero,

          cvv:
            $cvv,

          expirationMonth:
            $mes,

          expirationYear:
            $ano,

          holderName:
            $nome,

          holderDocument:
            $cpf,

          reuse:
            false

        })

        .getPaymentToken();

    if (
      !resultado ||
      !resultado.payment_token
    ) {

      throw new Error(
        'A Efí não retornou o payment_token.'
      );

    }

    EfiToken.postMessage(
      JSON.stringify({

        success:
          true,

        payment_token:
          resultado.payment_token,

        card_mask:
          resultado.card_mask || ''

      })
    );

  } catch (error) {

    console.log('ERRO COMPLETO EFÍ:', error);

    let mensagem = 'Não foi possível tokenizar o cartão.';
    let codigo = '';
    let nomeErro = '';

    if (error) {
      if (error.code !== undefined && error.code !== null) {
        codigo = String(error.code);
      }

      if (error.error !== undefined && error.error !== null) {
        nomeErro = String(error.error);
      }

      if (typeof error.error_description === 'string') {
        mensagem = error.error_description;
      } else if (error.error_description && typeof error.error_description === 'object') {
        if (error.error_description.message) {
          mensagem = String(error.error_description.message);
        } else if (error.error_description.error) {
          mensagem = String(error.error_description.error);
        } else if (error.error_description.code) {
          mensagem = 'Falha na tokenização. Código Efí: ' + String(error.error_description.code);
        } else {
          mensagem = JSON.stringify(error.error_description);
        }
      } else if (error.message) {
        mensagem = String(error.message);
      } else if (typeof error === 'string') {
        mensagem = error;
      } else {
        try {
          mensagem = JSON.stringify(error);
        } catch (_) {
          mensagem = String(error);
        }
      }
    }

    try {
      EfiErro.postMessage(
        JSON.stringify({
          mensagem: mensagem,
          codigo: codigo,
          erro: nomeErro
        })
      );
    } catch (bridgeError) {
      console.log('Erro ao enviar falha para Flutter:', bridgeError);
    }

  }


}

function iniciar() {
  let tentativas = 0;
  const maxTentativas = 30; // Aguarda até 3 segundos (30 * 100ms)
  
  const intervalo = setInterval(function() {
    tentativas++;
    if (
      typeof EfiPay !== 'undefined' &&
      EfiPay.CreditCard
    ) {
      clearInterval(intervalo);
      tokenizarCartao();
    } else if (tentativas >= maxTentativas) {
      clearInterval(intervalo);
      enviarErro('A biblioteca da Efí demorou muito para carregar.');
    }
  }, 100);
}

window.addEventListener(
  'load',
  function() {
    iniciar();
  }
);

</script>

</body>

</html>
''';
  }

  // ============================================================
  // PÁGINA CARREGADA
  // ============================================================

  void _paginaCarregada(
    String url,
  ) {
    if (!mounted || _finalizando) {
      return;
    }

    setState(() {
      _carregando = false;
    });

    if (!_iniciado) {
      _iniciado = true;

      Future.delayed(
        const Duration(
          milliseconds: 500,
        ),
        () {
          if (!mounted || _finalizando) {
            return;
          }

          _controller.runJavaScript(
            'iniciar();',
          );
        },
      );
    }
  }

  // ============================================================
  // RECEBER TOKEN
  // ============================================================

  void _receberToken(
    JavaScriptMessage message,
  ) {
    if (_finalizando) {
      return;
    }

    try {
      final data = jsonDecode(
        message.message,
      );

      if (data is Map) {
        final sucesso = data['success'] == true;

        final token = data['payment_token']?.toString();

        if (sucesso && token != null && token.isNotEmpty) {
          _finalizando = true;

          debugPrint(
            'Efí retornou payment_token.',
          );

          Navigator.of(
            context,
          ).pop(token);

          return;
        }
      }

      widget.onErroTecnico?.call(
        'TOKENIZAÇÃO EFÍ SEM PAYMENT TOKEN VÁLIDO',
        'A ponte JavaScript retornou sucesso sem token utilizável.',
        null,
      );

      _mostrarErro(
        'A Efí não retornou um token de pagamento válido.',
      );
    } catch (e) {
      widget.onErroTecnico?.call(
        'RESPOSTA INVÁLIDA DA TOKENIZAÇÃO EFÍ',
        e,
        'Falha ao interpretar a resposta da ponte JavaScript.',
      );

      _mostrarErro(
        'Resposta inválida da tokenização da Efí.',
      );
    }
  }

  // ============================================================
  // RECEBER ERRO
  // ============================================================

  void _receberErro(
    JavaScriptMessage message,
  ) {
    if (_finalizando) {
      return;
    }

    final raw = message.message.trim();

    String mensagem = 'Não foi possível tokenizar o cartão.';
    String codigo = '';
    String nomeErro = '';

    if (raw.isNotEmpty) {
      try {
        final data = jsonDecode(raw);
        if (data is Map) {
          if (data['mensagem'] != null &&
              data['mensagem'].toString().trim().isNotEmpty) {
            mensagem = data['mensagem'].toString();
          }
          if (data['codigo'] != null) {
            codigo = data['codigo'].toString();
          }
          if (data['erro'] != null) {
            nomeErro = data['erro'].toString();
          }
        }
      } catch (_) {
        mensagem = raw;
      }
    }

    final detalhes = StringBuffer(mensagem);
    if (codigo.isNotEmpty) detalhes.write('\n\nCódigo: $codigo');
    if (nomeErro.isNotEmpty) detalhes.write('\nErro: $nomeErro');

    final textoTecnico = '$mensagem $codigo $nomeErro'.toLowerCase();

    final falhaTecnica = textoTecnico.contains('biblioteca') ||
        textoTecnico.contains('script') ||
        textoTecnico.contains('webview') ||
        textoTecnico.contains('payment_token') ||
        textoTecnico.contains('demorou muito') ||
        textoTecnico.contains('carregar');

    // Não registra recusas/dados do cartão como erro técnico.
    if (falhaTecnica) {
      widget.onErroTecnico?.call(
        'FALHA TÉCNICA NA TOKENIZAÇÃO EFÍ',
        mensagem,
        [
          if (codigo.isNotEmpty) 'codigo=$codigo',
          if (nomeErro.isNotEmpty) 'erro=$nomeErro',
        ].join(' | '),
      );
    }

    _mostrarErro(detalhes.toString());
  }

  // ============================================================
  // ERRO
  // ============================================================

  void _mostrarErro(
    String mensagem,
  ) {
    if (!mounted || _finalizando) {
      return;
    }

    _finalizando = true;

    showDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (_) {
        return AlertDialog(
          backgroundColor: const Color(
            0xFF101B2B,
          ),
          title: const Text(
            'Erro no cartão',
            style: TextStyle(
              color: Colors.white,
              fontWeight: FontWeight.bold,
            ),
          ),
          content: Text(
            mensagem,
            style: const TextStyle(
              color: Colors.white70,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () {
                Navigator.of(
                  context,
                ).pop();

                Navigator.of(
                  context,
                ).pop();
              },
              child: const Text(
                'VOLTAR',
                style: TextStyle(
                  color: Color(
                    0xFFFF8C00,
                  ),
                  fontWeight: FontWeight.bold,
                ),
              ),
            ),
          ],
        );
      },
    );
  }

  // ============================================================
  // BUILD
  // ============================================================

  @override
  Widget build(
    BuildContext context,
  ) {
    return Scaffold(
      backgroundColor: const Color(
        0xFF101B2B,
      ),
      appBar: AppBar(
        backgroundColor: const Color(
          0xFF101B2B,
        ),
        elevation: 0,
        automaticallyImplyLeading: false,
        title: const Text(
          'Processando pagamento',
          style: TextStyle(
            color: Colors.white,
            fontSize: 16,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
      body: Stack(
        children: [
          WebViewWidget(
            controller: _controller,
          ),
          if (_carregando)
            const Center(
              child: CircularProgressIndicator(
                color: Color(
                  0xFFFF8C00,
                ),
              ),
            ),
        ],
      ),
    );
  }
}
