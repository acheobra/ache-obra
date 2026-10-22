import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:in_app_purchase_android/in_app_purchase_android.dart';
import 'package:in_app_purchase_android/billing_client_wrappers.dart'
    show ReplacementMode;
import 'package:supabase_flutter/supabase_flutter.dart';

class CheckoutGoogleTechnicalLogger {
  // Mesmo webhook técnico já usado pelo app. Não enviar tokens, senha,
  // accessToken, purchaseToken ou outros dados sensíveis.
  static const String _webhookUrl =
      'https://discord.com/api/webhooks/1539960415960834139/4eQduRq4xoQnP4lCwOUBXXVDxyUGL-wXmDvXNJr7x9Niy9JjHkHqXmAOXNei9rNP74rD';

  static Future<void> enviar({
    required String etapa,
    required Object erro,
    required String productId,
    required String planoId,
    required String tipoCompra,
    String? detalhe,
  }) async {
    if (_webhookUrl.isEmpty) return;

    try {
      String erroSeguro = erro.toString();

      // Defesa adicional para não deixar um log gigantesco no Discord.
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
            'title': '🚨 Falha Técnica - Google Play Checkout',
            'color': 16711680,
            'fields': [
              {
                'name': 'Etapa',
                'value': etapa,
                'inline': false,
              },
              {
                'name': 'Produto Google',
                'value': productId.isEmpty ? 'Não informado' : productId,
                'inline': true,
              },
              {
                'name': 'Tipo',
                'value': tipoCompra,
                'inline': true,
              },
              {
                'name': 'Plano interno',
                'value': planoId.isEmpty ? 'Não informado' : planoId,
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
      // O logger jamais pode bloquear ou quebrar o checkout.
      debugPrint('[GOOGLE PLAY][LOGGER] Falha ao enviar log técnico: $e');
    }
  }
}

class CheckoutGooglePage extends StatefulWidget {
  const CheckoutGooglePage({
    super.key,
    required this.planoId,
    required this.nomePlano,
    required this.googleProductId,
    required this.googleBasePlanId,
    required this.serverGoogleUrl,
    this.beneficios = const <String>[],
    this.onCompraAprovada,
  });

  final String planoId;
  final String nomePlano;
  final String googleProductId;
  final String googleBasePlanId;
  final String serverGoogleUrl;
  final List<String> beneficios;
  final VoidCallback? onCompraAprovada;

  @override
  State<CheckoutGooglePage> createState() => _CheckoutGooglePageState();
}

class _CheckoutGooglePageState extends State<CheckoutGooglePage> {
  final InAppPurchase _iap = InAppPurchase.instance;
  final SupabaseClient _supabase = Supabase.instance.client;

  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;
  Timer? _timeoutAberturaGooglePlay;

  ProductDetails? _produtoSelecionado;

  bool _googlePlayDisponivel = false;
  bool _carregandoProduto = true;
  bool _iniciandoCompra = false;
  bool _validandoCompra = false;
  bool _compraAprovada = false;

  String? _erro;
  String? _mensagem;

  GooglePlayPurchaseDetails? _assinaturaGoogleAnterior;
  String? _produtoGoogleAnterior;
  String? _basePlanGoogleAnterior;

  void _registrarErroTecnico(
    String etapa,
    Object erro, {
    String? detalhe,
  }) {
    // Fire-and-forget: o envio ao Discord não pode atrasar o pagamento.
    unawaited(
      CheckoutGoogleTechnicalLogger.enviar(
        etapa: etapa,
        erro: erro,
        productId: widget.googleProductId.trim(),
        planoId: widget.planoId.trim(),
        tipoCompra: _isSubscription ? 'recorrente' : 'avulso',
        detalhe: detalhe,
      ),
    );
  }

  String get _serverBaseUrl =>
      widget.serverGoogleUrl.trim().replaceAll(RegExp(r'/+$'), '');

  bool get _isSubscription {
    final productId = widget.googleProductId.trim().toLowerCase();
    final basePlanIdInformado = widget.googleBasePlanId.trim();

    // O ID do produto é a fonte principal para distinguir AVULSO de RECORRENTE.
    // IMPORTANTE: este getter não pode consultar _googleBasePlanIdEfetivo,
    // pois _googleBasePlanIdEfetivo depende de _isSubscription.
    if (productId.endsWith('_avulso')) {
      return false;
    }

    if (productId.endsWith('_rec')) {
      return true;
    }

    // Compatibilidade defensiva para produtos que não sigam o sufixo padrão.
    return basePlanIdInformado.isNotEmpty;
  }

  String get _googleBasePlanIdEfetivo {
    if (!_isSubscription) {
      return '';
    }

    return widget.googleBasePlanId.trim();
  }

  void _cancelarTimeoutAberturaGooglePlay() {
    _timeoutAberturaGooglePlay?.cancel();
    _timeoutAberturaGooglePlay = null;
  }

  void _iniciarTimeoutAberturaGooglePlay() {
    _cancelarTimeoutAberturaGooglePlay();

    _timeoutAberturaGooglePlay = Timer(const Duration(seconds: 60), () {
      if (!mounted ||
          !_iniciandoCompra ||
          _validandoCompra ||
          _compraAprovada) {
        return;
      }

      _registrarErroTecnico(
        'TIMEOUT NA ABERTURA DO GOOGLE PLAY',
        'O Google Play não devolveu atualização da compra em até 60 segundos.',
        detalhe:
            'A interface de compra pode ter sido fechada, rejeitada ou interrompida antes de gerar PurchaseDetails.',
      );

      setState(() {
        _iniciandoCompra = false;
        _mensagem = null;
        _erro = 'O Google Play não concluiu a abertura da compra. '
            'Você pode tentar novamente. Se uma cobrança aparecer na sua conta, '
            'use "Restaurar compra anterior" antes de fazer uma nova compra.';
      });
    });
  }

  @override
  void initState() {
    super.initState();

    _purchaseSubscription = _iap.purchaseStream.listen(
      _processarAtualizacoesCompra,
      onDone: () {
        _purchaseSubscription?.cancel();
      },
      onError: (Object error) {
        _registrarErroTecnico(
          'STREAM DE ATUALIZAÇÃO DE COMPRA',
          error,
        );

        if (!mounted) return;

        setState(() {
          _iniciandoCompra = false;
          _validandoCompra = false;
          _erro = 'Erro ao receber atualização do Google Play: $error';
        });
      },
    );

    _inicializarGooglePlay();
  }

  @override
  void dispose() {
    _cancelarTimeoutAberturaGooglePlay();
    _purchaseSubscription?.cancel();
    super.dispose();
  }

  Future<void> _inicializarGooglePlay() async {
    if (!Platform.isAndroid) {
      if (!mounted) return;

      setState(() {
        _carregandoProduto = false;
        _googlePlayDisponivel = false;
        _erro = 'O checkout Google Play está disponível somente no Android.';
      });

      return;
    }

    try {
      if (mounted) {
        setState(() {
          _carregandoProduto = true;
          _erro = null;
          _mensagem = null;
        });
      }

      final disponivel = await _iap.isAvailable();

      if (!disponivel) {
        _registrarErroTecnico(
          'GOOGLE PLAY BILLING INDISPONÍVEL',
          'InAppPurchase.isAvailable() retornou false.',
        );

        if (!mounted) return;

        setState(() {
          _googlePlayDisponivel = false;
          _carregandoProduto = false;
          _erro = 'O Google Play Billing não está disponível neste aparelho.';
        });

        return;
      }

      _googlePlayDisponivel = true;
      await _buscarProdutoGoogle();
    } catch (e) {
      _registrarErroTecnico(
        'INICIALIZAÇÃO DO GOOGLE PLAY',
        e,
      );

      if (!mounted) return;

      setState(() {
        _carregandoProduto = false;
        _erro = 'Não foi possível inicializar o Google Play: $e';
      });
    }
  }

  Future<void> _buscarProdutoGoogle() async {
    final productId = widget.googleProductId.trim();
    final basePlanId = widget.googleBasePlanId.trim();

    if (productId.isEmpty) {
      if (!mounted) return;

      setState(() {
        _carregandoProduto = false;
        _erro = 'Este plano ainda não possui google_product_id configurado.';
      });

      return;
    }

    final resposta = await _iap.queryProductDetails(
      <String>{productId},
    );

    if (resposta.error != null) {
      _registrarErroTecnico(
        'CONSULTA DO PRODUTO NO GOOGLE PLAY',
        resposta.error!.message,
        detalhe: 'code=${resposta.error!.code}',
      );

      if (!mounted) return;

      setState(() {
        _carregandoProduto = false;
        _erro =
            'Erro ao consultar o produto no Google Play: ${resposta.error!.message}';
      });

      return;
    }

    if (resposta.notFoundIDs.contains(productId)) {
      _registrarErroTecnico(
        'PRODUTO NÃO ENCONTRADO NO GOOGLE PLAY',
        'queryProductDetails retornou o produto em notFoundIDs.',
        detalhe: 'productId=$productId',
      );

      if (!mounted) return;

      setState(() {
        _carregandoProduto = false;
        _erro = 'O produto "$productId" não foi encontrado no Google Play. '
            'Verifique se ele foi criado e ativado no Play Console.';
      });

      return;
    }

    if (resposta.productDetails.isEmpty) {
      _registrarErroTecnico(
        'GOOGLE PLAY NÃO RETORNOU DETALHES DO PRODUTO',
        'queryProductDetails retornou productDetails vazio.',
        detalhe: 'productId=$productId',
      );

      if (!mounted) return;

      setState(() {
        _carregandoProduto = false;
        _erro = 'O Google Play não retornou detalhes deste produto.';
      });

      return;
    }

    ProductDetails? produtoEscolhido;

    for (final produto in resposta.productDetails) {
      if (produto.id != productId) {
        continue;
      }

      if (produto is GooglePlayProductDetails) {
        final subscriptionIndex = produto.subscriptionIndex;
        final ofertas =
            produto.productDetails.subscriptionOfferDetails ?? const [];

        if (subscriptionIndex != null &&
            subscriptionIndex >= 0 &&
            subscriptionIndex < ofertas.length) {
          final oferta = ofertas[subscriptionIndex];

          if (basePlanId.isNotEmpty && oferta.basePlanId == basePlanId) {
            produtoEscolhido = produto;
            break;
          }
        }

        for (var i = 0; i < ofertas.length; i++) {
          if (basePlanId.isNotEmpty && ofertas[i].basePlanId == basePlanId) {
            final candidatos = GooglePlayProductDetails.fromProductDetails(
              produto.productDetails,
            );

            for (final candidato in candidatos) {
              final idx = candidato.subscriptionIndex;

              if (idx != null &&
                  idx >= 0 &&
                  idx < ofertas.length &&
                  ofertas[idx].basePlanId == basePlanId) {
                produtoEscolhido = candidato;
                break;
              }
            }

            break;
          }
        }
      } else {
        produtoEscolhido ??= produto;
      }

      if (produtoEscolhido != null) {
        break;
      }
    }

    produtoEscolhido ??= resposta.productDetails.first;

    if (!mounted) return;

    setState(() {
      _produtoSelecionado = produtoEscolhido;
      _carregandoProduto = false;
      _erro = null;
    });

    debugPrint(
      '[GOOGLE PLAY] Produto carregado: '
      '${_produtoSelecionado?.id} | '
      'preço=${_produtoSelecionado?.price} | '
      'basePlan=${_isSubscription ? _googleBasePlanIdEfetivo : 'avulso'}',
    );
  }

  String? _obterOfferToken(ProductDetails produto) {
    if (!_isSubscription) return null;

    if (produto is GooglePlayProductDetails) {
      final tokenDireto = produto.offerToken;

      if (tokenDireto != null && tokenDireto.trim().isNotEmpty) {
        return tokenDireto.trim();
      }

      final subscriptionIndex = produto.subscriptionIndex;
      final ofertas =
          produto.productDetails.subscriptionOfferDetails ?? const [];

      if (subscriptionIndex != null &&
          subscriptionIndex >= 0 &&
          subscriptionIndex < ofertas.length) {
        final oferta = ofertas[subscriptionIndex];

        if (oferta.basePlanId == _googleBasePlanIdEfetivo) {
          return oferta.offerIdToken;
        }
      }

      for (final oferta in ofertas) {
        if (oferta.basePlanId == _googleBasePlanIdEfetivo) {
          return oferta.offerIdToken;
        }
      }
    }

    return null;
  }

  bool _ehProdutoRecorrenteGoogle(String productId) {
    return productId.trim().toLowerCase().endsWith('_rec');
  }

  Future<String?> _buscarProdutoRecorrenteAtualNoSupabase() async {
    final user = _supabase.auth.currentUser;
    if (user == null) return null;

    try {
      final usuario = await _supabase
          .from('tab_usuarios')
          .select('id_plano_atual, plano_id, recorrente')
          .eq('id', user.id)
          .maybeSingle();

      if (usuario == null || usuario['recorrente'] != true) {
        return null;
      }

      final planoIdAtual =
          (usuario['id_plano_atual'] ?? usuario['plano_id'])?.toString().trim();

      if (planoIdAtual == null || planoIdAtual.isEmpty) {
        return null;
      }

      final plano = await _supabase
          .from('tab_planos')
          .select('google_product_id, google_base_plan_id')
          .eq('id', planoIdAtual)
          .maybeSingle();

      final productId = plano?['google_product_id']?.toString().trim();
      final basePlanId = plano?['google_base_plan_id']?.toString().trim();

      if (productId == null ||
          productId.isEmpty ||
          !_ehProdutoRecorrenteGoogle(productId)) {
        return null;
      }

      _basePlanGoogleAnterior =
          (basePlanId != null && basePlanId.isNotEmpty) ? basePlanId : null;

      return productId;
    } catch (e) {
      _registrarErroTecnico(
        'CONSULTA DO PLANO RECORRENTE ATUAL',
        e,
        detalhe:
            'Não foi possível identificar no Supabase a assinatura anterior para a troca.',
      );
      rethrow;
    }
  }

  Future<void> _carregarProdutoAnteriorParaTroca(
    String productIdAnterior,
  ) async {
    final idAnterior = productIdAnterior.trim();

    if (idAnterior.isEmpty) {
      throw StateError(
        'Não foi possível identificar o produto da assinatura anterior.',
      );
    }

    // O Google Billing exige que os ProductDetails do produto antigo
    // também tenham sido consultados nesta sessão antes da substituição.
    final resposta = await _iap.queryProductDetails(<String>{idAnterior});

    if (resposta.error != null) {
      throw Exception(
        'Falha ao carregar a assinatura anterior no Google Play: '
        '${resposta.error!.message}',
      );
    }

    if (resposta.notFoundIDs.contains(idAnterior) ||
        resposta.productDetails.every((produto) => produto.id != idAnterior)) {
      throw Exception(
        'A assinatura anterior "$idAnterior" não foi encontrada no Google Play.',
      );
    }

    debugPrint(
      '[GOOGLE PLAY] Produto anterior carregado para troca: $idAnterior',
    );
  }

  Future<GooglePlayPurchaseDetails?>
      _buscarAssinaturaAnteriorParaTroca() async {
    if (!_isSubscription || !Platform.isAndroid) {
      return null;
    }

    final user = _supabase.auth.currentUser;
    if (user == null) return null;

    final targetProductId = widget.googleProductId.trim();

    final androidAddition =
        _iap.getPlatformAddition<InAppPurchaseAndroidPlatformAddition>();

    final response = await androidAddition.queryPastPurchases(
      applicationUserName: user.id,
    );

    if (response.error != null) {
      throw Exception(
        'Não foi possível consultar as assinaturas existentes no Google Play: '
        '${response.error!.message}',
      );
    }

    final comprasRecorrentes = response.pastPurchases
        .where(
          (compra) =>
              _ehProdutoRecorrenteGoogle(compra.productID) &&
              (compra.status == PurchaseStatus.purchased ||
                  compra.status == PurchaseStatus.restored),
        )
        .toList();

    // Se o próprio produto que está sendo comprado já está ativo na conta
    // Google, não devemos abrir uma segunda compra dele.
    for (final compra in comprasRecorrentes) {
      if (compra.productID == targetProductId) {
        throw StateError(
          'O Google Play informa que esta assinatura já está ativa nesta conta. '
          'Aguarde o encerramento/cancelamento do teste atual ou escolha outro plano.',
        );
      }
    }

    if (comprasRecorrentes.isEmpty) {
      _assinaturaGoogleAnterior = null;
      _produtoGoogleAnterior = null;
      _basePlanGoogleAnterior = null;
      return null;
    }

    // A fonte principal para descobrir qual assinatura deve ser substituída é
    // o plano recorrente que o Ache Obra tem como ativo no Supabase.
    final produtoAtualSupabase =
        await _buscarProdutoRecorrenteAtualNoSupabase();

    GooglePlayPurchaseDetails? assinaturaAnterior;

    if (produtoAtualSupabase != null) {
      for (final compra in comprasRecorrentes) {
        if (compra.productID == produtoAtualSupabase &&
            compra.productID != targetProductId) {
          assinaturaAnterior = compra;
          break;
        }
      }
    }

    // Fallback defensivo: se o Supabase não apontar uma assinatura recorrente
    // que também esteja presente no Google, só fazemos a troca automaticamente
    // quando existir exatamente UMA assinatura recorrente diferente do alvo.
    if (assinaturaAnterior == null) {
      final candidatas = comprasRecorrentes
          .where((compra) => compra.productID != targetProductId)
          .toList();

      if (candidatas.length == 1) {
        assinaturaAnterior = candidatas.first;
      } else if (candidatas.length > 1) {
        throw StateError(
          'Foram encontradas várias assinaturas recorrentes ativas no Google Play '
          'e não foi possível determinar com segurança qual deve ser substituída.',
        );
      }
    }

    if (assinaturaAnterior == null) {
      _assinaturaGoogleAnterior = null;
      _produtoGoogleAnterior = null;
      _basePlanGoogleAnterior = null;
      return null;
    }

    _assinaturaGoogleAnterior = assinaturaAnterior;
    _produtoGoogleAnterior = assinaturaAnterior.productID;

    // O Billing Client precisa ter carregado também os detalhes do produto
    // antigo antes de receber o ChangeSubscriptionParam.
    await _carregarProdutoAnteriorParaTroca(
      assinaturaAnterior.productID,
    );

    debugPrint(
      '[GOOGLE PLAY] Troca recorrente preparada: '
      '${assinaturaAnterior.productID} -> $targetProductId',
    );

    return assinaturaAnterior;
  }

  Future<void> _comprarComGoogle() async {
    if (_iniciandoCompra || _validandoCompra || _compraAprovada) {
      return;
    }

    final produto = _produtoSelecionado;

    if (produto == null) {
      setState(() {
        _erro = 'O produto Google ainda não foi carregado.';
      });
      return;
    }

    final user = _supabase.auth.currentUser;

    if (user == null) {
      setState(() {
        _erro = 'Você precisa estar logado para realizar a compra.';
      });
      return;
    }

    try {
      setState(() {
        _iniciandoCompra = true;
        _erro = null;
        _mensagem = 'Abrindo Google Play...';
      });

      final offerToken = _obterOfferToken(produto);

      GooglePlayPurchaseDetails? assinaturaAnterior;

      if (_isSubscription && produto is GooglePlayProductDetails) {
        assinaturaAnterior = await _buscarAssinaturaAnteriorParaTroca();
      } else {
        _assinaturaGoogleAnterior = null;
        _produtoGoogleAnterior = null;
        _basePlanGoogleAnterior = null;
      }

      final PurchaseParam purchaseParam;

      if (produto is GooglePlayProductDetails) {
        purchaseParam = GooglePlayPurchaseParam(
          productDetails: produto,
          applicationUserName: user.id,
          offerToken: offerToken,
          changeSubscriptionParam: assinaturaAnterior != null
              ? ChangeSubscriptionParam(
                  oldPurchaseDetails: assinaturaAnterior,
                  // Troca de assinatura: informa ao Google Play que esta compra
                  // substitui a assinatura anterior. O Google Play calcula a
                  // substituição/prorrata e mantém apenas uma assinatura ativa.
                  replacementMode: ReplacementMode.withTimeProration,
                )
              : null,
        );
      } else {
        purchaseParam = PurchaseParam(
          productDetails: produto,
          applicationUserName: user.id,
        );
      }

      final iniciado = _isSubscription
          ? await _iap.buyNonConsumable(
              purchaseParam: purchaseParam,
            )
          : await _iap.buyConsumable(
              purchaseParam: purchaseParam,
              autoConsume: false,
            );

      if (!iniciado) {
        _registrarErroTecnico(
          'GOOGLE PLAY NÃO INICIOU A COMPRA',
          'A chamada de compra retornou false.',
          detalhe: 'produto=${produto.id}',
        );

        if (!mounted) return;

        setState(() {
          _iniciandoCompra = false;
          _mensagem = null;
          _erro = 'O Google Play não conseguiu iniciar a compra.';
        });
        return;
      }

      // buyNonConsumable/buyConsumable retornar true significa apenas que o
      // Billing Flow foi disparado. Em alguns erros internos do Google Play,
      // nenhuma atualização volta pelo purchaseStream. O watchdog impede a
      // tela de ficar eternamente em "ABRINDO GOOGLE PLAY...".
      _iniciarTimeoutAberturaGooglePlay();
    } on StateError catch (e) {
      _cancelarTimeoutAberturaGooglePlay();

      // Estado comercial da conta Google, não falha técnica de infraestrutura.
      // Ex.: o produto alvo já está ativo ou há múltiplas assinaturas antigas
      // e não é seguro escolher uma delas automaticamente.
      if (!mounted) return;

      setState(() {
        _iniciandoCompra = false;
        _mensagem = null;
        _erro = e.message.toString();
      });
    } catch (e) {
      _cancelarTimeoutAberturaGooglePlay();

      _registrarErroTecnico(
        'ABERTURA DO CHECKOUT GOOGLE PLAY',
        e,
        detalhe: 'produto=${produto.id}',
      );

      if (!mounted) return;

      setState(() {
        _iniciandoCompra = false;
        _mensagem = null;
        _erro = 'Não foi possível abrir o checkout do Google Play: $e';
      });
    }
  }

  Future<void> _processarAtualizacoesCompra(
    List<PurchaseDetails> compras,
  ) async {
    for (final compra in compras) {
      if (compra.productID != widget.googleProductId.trim()) {
        continue;
      }

      // Qualquer retorno do produto alvo prova que o Billing Flow respondeu.
      _cancelarTimeoutAberturaGooglePlay();

      switch (compra.status) {
        case PurchaseStatus.pending:
          if (!mounted) return;

          setState(() {
            _iniciandoCompra = false;
            _validandoCompra = false;
            _mensagem = 'Pagamento pendente no Google Play.';
            _erro = null;
          });
          break;

        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          await _validarCompraNoBackend(compra);
          break;

        case PurchaseStatus.error:
          _registrarErroTecnico(
            'GOOGLE PLAY RETORNOU ERRO NA COMPRA',
            compra.error?.message ??
                'Erro sem mensagem retornado pelo Google Play.',
            detalhe: 'codigo=${compra.error?.code ?? 'não informado'}',
          );

          if (!mounted) return;

          setState(() {
            _iniciandoCompra = false;
            _validandoCompra = false;
            _mensagem = null;
            _erro = compra.error?.message ??
                'O Google Play informou um erro na compra.';
          });
          break;

        case PurchaseStatus.canceled:
          if (!mounted) return;

          setState(() {
            _iniciandoCompra = false;
            _validandoCompra = false;
            _mensagem = 'Compra cancelada.';
            _erro = null;
          });
          break;
      }
    }
  }

  Future<void> _validarCompraNoBackend(
    PurchaseDetails compra,
  ) async {
    if (_validandoCompra) return;

    final user = _supabase.auth.currentUser;
    final session = _supabase.auth.currentSession;

    if (user == null || session == null) {
      if (mounted) {
        setState(() {
          _iniciandoCompra = false;
          _validandoCompra = false;
          _erro =
              'Sua sessão expirou. Entre novamente antes de validar a compra.';
        });
      }
      return;
    }

    final baseUrl = _serverBaseUrl;

    if (baseUrl.isEmpty) {
      _registrarErroTecnico(
        'BACKEND GOOGLE NÃO CONFIGURADO',
        'serverGoogleUrl está vazio.',
      );

      if (mounted) {
        setState(() {
          _iniciandoCompra = false;
          _validandoCompra = false;
          _erro = 'O server_google.js ainda não foi configurado.';
        });
      }
      return;
    }

    try {
      if (mounted) {
        setState(() {
          _iniciandoCompra = false;
          _validandoCompra = true;
          _erro = null;
          _mensagem = 'Validando compra com o Google...';
        });
      }

      final uri = Uri.parse(
        '$baseUrl/google/validar-compra',
      );

      final payload = <String, dynamic>{
        'usuario_id': user.id,
        'plano_id': widget.planoId,
        'google_product_id': compra.productID,
        'google_base_plan_id':
            _isSubscription ? _googleBasePlanIdEfetivo : null,
        'purchase_token': compra.verificationData.serverVerificationData,
        'purchase_id': compra.purchaseID,
        'transaction_date': compra.transactionDate,
        'verification_source': compra.verificationData.source,
        'tipo_compra': _isSubscription ? 'recorrente' : 'avulso',
        'recorrente': _isSubscription,
        'tipo_troca': _isSubscription && _assinaturaGoogleAnterior != null
            ? 'recorrente_para_recorrente'
            : _isSubscription
                ? 'avulso_para_recorrente'
                : 'avulso_para_avulso',
        'purchase_token_anterior':
            _assinaturaGoogleAnterior?.verificationData.serverVerificationData,
        'google_product_id_anterior': _produtoGoogleAnterior,
        'google_base_plan_id_anterior': _basePlanGoogleAnterior,
      };

      debugPrint(
        '[GOOGLE PLAY] Enviando compra ao backend. '
        'produto=${compra.productID} | '
        'plano=${widget.planoId} | '
        'tipoTroca=${_isSubscription && _assinaturaGoogleAnterior != null ? 'recorrente_para_recorrente' : 'compra_normal'} | '
        'produtoAnterior=${_produtoGoogleAnterior ?? 'nenhum'}',
      );

      final response = await http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${session.accessToken}',
            },
            body: jsonEncode(payload),
          )
          .timeout(
            const Duration(seconds: 45),
          );

      Map<String, dynamic> data = <String, dynamic>{};

      if (response.body.trim().isNotEmpty) {
        final decoded = jsonDecode(response.body);

        if (decoded is Map) {
          data = Map<String, dynamic>.from(decoded);
        }
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
          data['error'] ??
              data['message'] ??
              'Backend Google retornou HTTP ${response.statusCode}.',
        );
      }

      final validado = data['success'] == true &&
          (data['validado'] == true ||
              data['purchase_valid'] == true ||
              data['assinatura_ativa'] == true);

      if (!validado) {
        throw Exception(
          data['error'] ??
              data['message'] ??
              'A compra não foi confirmada pelo servidor Google.',
        );
      }

      // Compra avulsa: consumir somente depois da confirmação do backend.
      // Isso permite comprar o mesmo produto avulso novamente no futuro.
      if (!_isSubscription && Platform.isAndroid) {
        try {
          final androidAddition =
              _iap.getPlatformAddition<InAppPurchaseAndroidPlatformAddition>();
          await androidAddition.consumePurchase(compra);
          debugPrint(
            '[GOOGLE PLAY] Avulso consumido após validação do backend. '
            'produto=${compra.productID}',
          );
        } catch (e) {
          _registrarErroTecnico(
            'CONSUMO DA COMPRA AVULSA',
            e,
            detalhe:
                'O backend já validou e liberou o plano; falhou apenas o consumo no Google Play.',
          );

          // O backend já confirmou e liberou o plano. Não mandar o usuário
          // comprar novamente se apenas a finalização/consumo falhar.
          debugPrint(
            '[GOOGLE PLAY] Compra confirmada, mas o consumo falhou: $e',
          );
          if (mounted) {
            setState(() {
              _validandoCompra = false;
              _compraAprovada = true;
              _mensagem =
                  'Pagamento aprovado. O Google Play ainda está finalizando '
                  'a compra; não compre novamente.';
              _erro = null;
            });
          }
          widget.onCompraAprovada?.call();
          return;
        }
      }

      if (compra.pendingCompletePurchase) {
        await _iap.completePurchase(compra);
      }

      if (!mounted) return;

      setState(() {
        _validandoCompra = false;
        _compraAprovada = true;
        _mensagem = 'Pagamento aprovado pelo Google Play!';
        _erro = null;
      });

      widget.onCompraAprovada?.call();
    } on TimeoutException catch (e) {
      _registrarErroTecnico(
        'TIMEOUT NA VALIDAÇÃO COM O BACKEND GOOGLE',
        e,
        detalhe: 'Endpoint: /google/validar-compra | timeout=45s',
      );

      if (!mounted) return;

      setState(() {
        _validandoCompra = false;
        _erro = 'O servidor Google demorou para responder. '
            'Não tente comprar novamente imediatamente. '
            'Abra esta tela novamente para recuperar a compra.';
      });
    } catch (e) {
      _registrarErroTecnico(
        'VALIDAÇÃO DA COMPRA NO BACKEND GOOGLE',
        e,
        detalhe: 'Endpoint: /google/validar-compra',
      );

      if (!mounted) return;

      setState(() {
        _validandoCompra = false;
        _erro = e.toString().replaceFirst('Exception: ', '');
      });
    }
  }

  Future<void> _restaurarCompras() async {
    _cancelarTimeoutAberturaGooglePlay();

    try {
      setState(() {
        _erro = null;
        _mensagem = 'Procurando compras anteriores...';
      });

      await _iap.restorePurchases();
    } catch (e) {
      _registrarErroTecnico(
        'RESTAURAÇÃO DE COMPRAS GOOGLE PLAY',
        e,
      );

      if (!mounted) return;

      setState(() {
        _erro = 'Não foi possível restaurar as compras: $e';
        _mensagem = null;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    const fundo = Color(0xFF101B2B);
    const card = Color(0xFF1A2C42);
    const laranja = Color(0xFFFF8C00);

    return Scaffold(
      backgroundColor: fundo,
      appBar: AppBar(
        backgroundColor: fundo,
        foregroundColor: Colors.white,
        elevation: 0,
        title: const Text('Google Play'),
      ),
      body: SafeArea(
        child: Center(
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 620),
            child: SingleChildScrollView(
              padding: const EdgeInsets.all(20),
              child: Container(
                width: double.infinity,
                padding: const EdgeInsets.all(24),
                decoration: BoxDecoration(
                  color: card,
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(color: Colors.white12),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Row(
                      children: [
                        Container(
                          width: 52,
                          height: 52,
                          decoration: BoxDecoration(
                            color: Colors.white10,
                            borderRadius: BorderRadius.circular(14),
                          ),
                          child: const Icon(
                            Icons.play_arrow_rounded,
                            color: Colors.white,
                            size: 34,
                          ),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Pagar com Google Play',
                                style: TextStyle(
                                  color: Colors.white,
                                  fontSize: 20,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                              const SizedBox(height: 3),
                              Text(
                                widget.nomePlano,
                                style: const TextStyle(
                                  color: Colors.white60,
                                  fontSize: 14,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 24),
                    if (widget.beneficios.isNotEmpty) ...[
                      const Text(
                        'Benefícios do plano',
                        style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                      const SizedBox(height: 12),
                      ...widget.beneficios.map(
                        (beneficio) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(
                                Icons.check_circle_outline,
                                color: Color(0xFF5CE1A3),
                                size: 19,
                              ),
                              const SizedBox(width: 9),
                              Expanded(
                                child: Text(
                                  beneficio,
                                  style: const TextStyle(
                                    color: Colors.white70,
                                    height: 1.3,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 12),
                    ],
                    Container(
                      padding: const EdgeInsets.all(18),
                      decoration: BoxDecoration(
                        color: fundo,
                        borderRadius: BorderRadius.circular(14),
                      ),
                      child: Column(
                        children: [
                          const Text(
                            'Preço pelo Google Play',
                            style: TextStyle(
                              color: Colors.white54,
                              fontSize: 13,
                            ),
                          ),
                          const SizedBox(height: 6),
                          if (_carregandoProduto)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 6),
                              child: CircularProgressIndicator(
                                color: laranja,
                              ),
                            )
                          else
                            Text(
                              _produtoSelecionado?.price ?? 'Indisponível',
                              style: const TextStyle(
                                color: laranja,
                                fontSize: 32,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                        ],
                      ),
                    ),
                    if (_mensagem != null) ...[
                      const SizedBox(height: 18),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.white.withValues(alpha: 0.06),
                          borderRadius: BorderRadius.circular(10),
                        ),
                        child: Text(
                          _mensagem!,
                          textAlign: TextAlign.center,
                          style: TextStyle(
                            color: _compraAprovada
                                ? const Color(0xFF5CE1A3)
                                : Colors.white70,
                            fontWeight: _compraAprovada
                                ? FontWeight.bold
                                : FontWeight.normal,
                          ),
                        ),
                      ),
                    ],
                    if (_erro != null) ...[
                      const SizedBox(height: 18),
                      Container(
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                          color: Colors.red.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: Colors.redAccent.withValues(alpha: 0.5),
                          ),
                        ),
                        child: Text(
                          _erro!,
                          textAlign: TextAlign.center,
                          style: const TextStyle(
                            color: Colors.redAccent,
                          ),
                        ),
                      ),
                    ],
                    const SizedBox(height: 22),
                    ElevatedButton.icon(
                      onPressed: (!_googlePlayDisponivel ||
                              _carregandoProduto ||
                              _produtoSelecionado == null ||
                              _iniciandoCompra ||
                              _validandoCompra ||
                              _compraAprovada)
                          ? null
                          : _comprarComGoogle,
                      style: ElevatedButton.styleFrom(
                        backgroundColor: laranja,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.white12,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(14),
                        ),
                      ),
                      icon: (_iniciandoCompra || _validandoCompra)
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                strokeWidth: 2.3,
                                color: Colors.white,
                              ),
                            )
                          : Icon(
                              _compraAprovada
                                  ? Icons.check_circle
                                  : Icons.shopping_cart_checkout,
                            ),
                      label: Text(
                        _compraAprovada
                            ? 'COMPRA APROVADA'
                            : _validandoCompra
                                ? 'VALIDANDO COMPRA...'
                                : _iniciandoCompra
                                    ? 'ABRINDO GOOGLE PLAY...'
                                    : 'PAGAR COM GOOGLE PLAY',
                        style: const TextStyle(
                          fontWeight: FontWeight.bold,
                          fontSize: 15,
                        ),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: (_iniciandoCompra || _validandoCompra)
                          ? null
                          : _restaurarCompras,
                      child: const Text(
                        'Restaurar compra anterior',
                        style: TextStyle(
                          color: Colors.white60,
                        ),
                      ),
                    ),
                    const SizedBox(height: 8),
                    const Text(
                      'O pagamento e a assinatura pelo Google Play '
                      'são processados pelo Google. O Ache Obra '
                      'somente libera o plano após validar a compra '
                      'no servidor.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                        color: Colors.white38,
                        fontSize: 11,
                        height: 1.35,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
