import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:flutter/material.dart';
import 'package:http/http.dart' as http;
import 'package:in_app_purchase/in_app_purchase.dart';
import 'package:supabase_flutter/supabase_flutter.dart';

/// Checkout Apple do Ache Obra.
///
/// O backend deve implementar POST /apple/validar-compra e verificar a
/// transação diretamente com a Apple. O plano só é liberado após validação
/// explícita do servidor. Este arquivo não altera o checkout Android/Efí.
class CheckoutApplePage extends StatefulWidget {
  const CheckoutApplePage({
    super.key,
    required this.planoId,
    required this.nomePlano,
    required this.appleProductId,
    required this.serverAppleUrl,
    this.recorrente = true,
    this.beneficios = const <String>[],
    this.onCompraAprovada,
  });

  final String planoId;
  final String nomePlano;
  final String appleProductId;
  final String serverAppleUrl;

  /// Informe false ao abrir um produto avulso.
  final bool recorrente;
  final List<String> beneficios;
  final VoidCallback? onCompraAprovada;

  @override
  State<CheckoutApplePage> createState() => _CheckoutApplePageState();
}

class _CheckoutApplePageState extends State<CheckoutApplePage> {
  final InAppPurchase _iap = InAppPurchase.instance;
  final SupabaseClient _supabase = Supabase.instance.client;

  StreamSubscription<List<PurchaseDetails>>? _purchaseSubscription;
  ProductDetails? _produtoSelecionado;

  bool _appleDisponivel = false;
  bool _carregandoProduto = true;
  bool _iniciandoCompra = false;
  bool _validandoCompra = false;
  bool _compraAprovada = false;

  // As atualizações do purchaseStream são processadas em série. O stream pode
  // entregar mais de uma atualização enquanto uma validação HTTP está em curso;
  // não descartamos eventos apenas porque outro evento está sendo processado.
  final List<PurchaseDetails> _filaAtualizacoesCompra = <PurchaseDetails>[];
  final Set<String> _eventosNaFila = <String>{};
  bool _processandoFila = false;

  // Mantém a PurchaseDetails recebida quando a validação falha. Isso permite
  // reenviar a MESMA transação ao backend, sem iniciar uma nova cobrança.
  PurchaseDetails? _compraPendenteValidacao;
  PurchaseDetails? _compraAguardandoApple;
  bool _bloqueioPorTransacaoDuplicada = false;

  String? _erro;
  String? _mensagem;

  String get _serverBaseUrl =>
      widget.serverAppleUrl.trim().replaceAll(RegExp(r'/+$'), '');

  String get _productId => widget.appleProductId.trim();

  bool get _isSubscription => widget.recorrente;

  @override
  void initState() {
    super.initState();
    // A assinatura do stream é criada antes da consulta do produto para
    // aumentar a chance de receber transações pendentes ao abrir este checkout.
    // Para recuperação mesmo quando esta tela não está aberta, o app também
    // deve manter um listener único no ciclo de vida global (main.dart).
    _purchaseSubscription = _iap.purchaseStream.listen(
      _receberAtualizacoesCompra,
      onDone: () => _purchaseSubscription?.cancel(),
      onError: (Object error) {
        if (!mounted) return;
        setState(() {
          _iniciandoCompra = false;
          _validandoCompra = false;
          _erro = 'Erro ao receber atualização da App Store: $error';
          _mensagem = null;
        });
      },
    );
    _inicializarApple();
  }

  @override
  void dispose() {
    _purchaseSubscription?.cancel();
    super.dispose();
  }

  Future<void> _inicializarApple() async {
    if (!Platform.isIOS) {
      if (!mounted) return;
      setState(() {
        _carregandoProduto = false;
        _appleDisponivel = false;
        _erro = 'O checkout Apple está disponível somente no iPhone/iPad.';
      });
      return;
    }

    if (_productId.isEmpty) {
      if (!mounted) return;
      setState(() {
        _carregandoProduto = false;
        _erro = 'Este plano ainda não possui apple_product_id configurado.';
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
        if (!mounted) return;
        setState(() {
          _appleDisponivel = false;
          _carregandoProduto = false;
          _erro = 'A App Store não está disponível neste aparelho ou conta.';
        });
        return;
      }

      _appleDisponivel = true;
      final resposta = await _iap.queryProductDetails(<String>{_productId});
      if (resposta.error != null) {
        throw Exception(
          'Erro ao consultar produto na App Store: ${resposta.error!.message}',
        );
      }
      if (resposta.notFoundIDs.contains(_productId) ||
          resposta.productDetails.every((p) => p.id != _productId)) {
        throw Exception(
          'O produto "$_productId" não foi encontrado na App Store. '
          'Confira o identificador no App Store Connect.',
        );
      }

      final produto =
          resposta.productDetails.firstWhere((p) => p.id == _productId);
      if (!mounted) return;
      setState(() {
        _produtoSelecionado = produto;
        _carregandoProduto = false;
        _erro = null;
      });
      debugPrint(
          '[APPLE] Produto carregado: ${produto.id} | preço=${produto.price}');
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _carregandoProduto = false;
        _erro = e.toString().replaceFirst('Exception: ', '');
      });
      debugPrint('[APPLE] Falha ao inicializar checkout: $e');
    }
  }

  Future<void> _comprarComApple() async {
    if (_iniciandoCompra || _validandoCompra || _compraAprovada) return;

    // Se o StoreKit já entregou uma transação, primeiro tentamos validar
    // essa transação. Nunca abrimos uma nova compra por cima dela.
    final compraPendente = _compraPendenteValidacao;
    if (compraPendente != null) {
      await _revalidarCompraPendente();
      return;
    }

    if (_compraAguardandoApple != null || _bloqueioPorTransacaoDuplicada) {
      if (mounted) {
        setState(() {
          _erro = 'Existe uma transação anterior deste produto ainda pendente '
              'na App Store. Não inicie outra compra. Use a opção de recuperação '
              'abaixo ou feche e abra novamente o Ache Obra para receber a '
              'atualização pendente do StoreKit.';
          _mensagem = null;
        });
      }
      return;
    }

    final produto = _produtoSelecionado;
    if (produto == null) {
      if (mounted)
        setState(() => _erro = 'O produto Apple ainda não foi carregado.');
      return;
    }

    final user = _supabase.auth.currentUser;
    if (user == null) {
      if (mounted) {
        setState(
            () => _erro = 'Você precisa estar logado para realizar a compra.');
      }
      return;
    }
    if (_serverBaseUrl.isEmpty) {
      if (mounted) {
        setState(() =>
            _erro = 'O endereço do backend Apple ainda não foi configurado.');
      }
      return;
    }

    try {
      setState(() {
        _iniciandoCompra = true;
        _erro = null;
        _mensagem = 'Abrindo a confirmação de compra da Apple...';
      });

      final purchaseParam = PurchaseParam(
        productDetails: produto,
        applicationUserName: user.id,
      );

      // Os produtos avulsos do projeto estão cadastrados como consumíveis;
      // as opções recorrentes são assinaturas não consumíveis no StoreKit.
      final iniciado = _isSubscription
          ? await _iap.buyNonConsumable(purchaseParam: purchaseParam)
          : await _iap.buyConsumable(
              purchaseParam: purchaseParam,
              autoConsume: false,
            );

      if (!iniciado && mounted) {
        setState(() {
          _iniciandoCompra = false;
          _mensagem = null;
          _erro = 'A App Store não conseguiu iniciar a compra.';
        });
      }
    } catch (e) {
      if (!mounted) return;
      final detalhe = e.toString();
      final duplicada =
          detalhe.toLowerCase().contains('storekit_duplicate_product_object') ||
              detalhe
                  .toLowerCase()
                  .contains('pending transaction for the same product');
      setState(() {
        _iniciandoCompra = false;
        _mensagem = null;
        if (duplicada) {
          _bloqueioPorTransacaoDuplicada = true;
          _erro = 'A Apple encontrou uma transação anterior ainda aberta para '
              'este produto. Nenhuma nova compra foi iniciada. Tente recuperar '
              'a transação pendente; não faça outra cobrança.';
        } else {
          _erro = 'Não foi possível abrir a compra da Apple: $detalhe';
        }
      });
      debugPrint(
          '[APPLE][COMPRA_INICIAR_FALHOU] produto=$_productId duplicada=$duplicada erro=$detalhe');
    }
  }

  String _chaveEventoCompra(PurchaseDetails compra) {
    final id = compra.purchaseID?.trim();
    final base = (id != null && id.isNotEmpty)
        ? id
        : '${compra.productID}|${compra.transactionDate ?? ''}|${identityHashCode(compra)}';
    return '$base|${compra.status.name}';
  }

  void _receberAtualizacoesCompra(List<PurchaseDetails> compras) {
    for (final compra in compras) {
      // Esta tela só pode validar o produto que foi efetivamente selecionado.
      // Transações de outros produtos não devem ser finalizadas aqui.
      if (compra.productID != _productId) {
        debugPrint(
            '[APPLE][STREAM_OUTRO_PRODUTO] recebido=${compra.productID} esperado=$_productId');
        continue;
      }

      final chave = _chaveEventoCompra(compra);
      if (_eventosNaFila.add(chave)) {
        _filaAtualizacoesCompra.add(compra);
      }
    }

    unawaited(_processarFilaAtualizacoesCompra());
  }

  Future<void> _processarFilaAtualizacoesCompra() async {
    if (_processandoFila) return;
    _processandoFila = true;

    try {
      while (_filaAtualizacoesCompra.isNotEmpty) {
        final compra = _filaAtualizacoesCompra.removeAt(0);
        final chave = _chaveEventoCompra(compra);
        try {
          await _processarUmaAtualizacaoCompra(compra);
        } catch (e, stack) {
          debugPrint('[APPLE][STREAM_PROCESSAMENTO_FALHOU] erro=$e\n$stack');
        } finally {
          _eventosNaFila.remove(chave);
        }
      }
    } finally {
      _processandoFila = false;
      // Se um evento chegou no instante em que a fila estava terminando,
      // garante que ele também seja processado.
      if (_filaAtualizacoesCompra.isNotEmpty) {
        unawaited(_processarFilaAtualizacoesCompra());
      }
    }
  }

  Future<void> _processarUmaAtualizacaoCompra(PurchaseDetails compra) async {
    debugPrint(
        '[APPLE][STREAM] produto=${compra.productID} status=${compra.status.name} '
        'transaction=${compra.purchaseID ?? '-'} pendingComplete=${compra.pendingCompletePurchase}');

    switch (compra.status) {
      case PurchaseStatus.pending:
        _compraAguardandoApple = compra;
        if (!mounted) return;
        setState(() {
          _iniciandoCompra = false;
          _validandoCompra = false;
          _mensagem = 'A Apple ainda está processando esta compra. Aguarde; '
              'não inicie outra compra deste mesmo produto.';
          _erro = null;
        });
        break;

      case PurchaseStatus.purchased:
      case PurchaseStatus.restored:
        _compraAguardandoApple = null;
        _bloqueioPorTransacaoDuplicada = false;
        await _validarCompraNoBackend(compra);
        break;

      case PurchaseStatus.error:
        _compraAguardandoApple = null;
        _compraPendenteValidacao = null;
        _bloqueioPorTransacaoDuplicada = false;
        if (mounted) {
          setState(() {
            _iniciandoCompra = false;
            _validandoCompra = false;
            _mensagem = null;
            _erro = compra.error?.message ??
                'A App Store informou um erro na compra.';
          });
        }
        // Erro/cancelamento não concede benefício. Se o plugin exigir a
        // conclusão da atualização, liberamos a fila local do StoreKit.
        if (compra.pendingCompletePurchase) await _finalizarCompra(compra);
        break;

      case PurchaseStatus.canceled:
        _compraAguardandoApple = null;
        _compraPendenteValidacao = null;
        _bloqueioPorTransacaoDuplicada = false;
        if (mounted) {
          setState(() {
            _iniciandoCompra = false;
            _validandoCompra = false;
            _mensagem = 'Compra cancelada.';
            _erro = null;
          });
        }
        if (compra.pendingCompletePurchase) await _finalizarCompra(compra);
        break;
    }
  }

  Future<void> _revalidarCompraPendente() async {
    final compra = _compraPendenteValidacao;
    if (compra == null) {
      await _verificarTransacaoPendente();
      return;
    }
    if (_validandoCompra) return;
    await _validarCompraNoBackend(compra);
  }

  Future<void> _verificarTransacaoPendente() async {
    if (_compraAguardandoApple != null) {
      if (!mounted) return;
      setState(() {
        _mensagem =
            'A transação continua pendente na Apple. Aguarde a atualização '
            'do StoreKit e não tente comprar novamente.';
        _erro = null;
      });
      return;
    }

    if (_isSubscription) {
      await _restaurarCompras();
      return;
    }

    if (!mounted) return;
    setState(() {
      _mensagem =
          'O StoreKit informou que existe uma transação avulsa anterior '
          'aberta, mas ainda não entregou seus dados ao aplicativo. Feche '
          'completamente o Ache Obra, abra novamente e entre neste mesmo produto. '
          'O aplicativo tentará receber e validar a transação pendente. Não faça '
          'uma nova compra enquanto esse aviso permanecer.';
      _erro = null;
    });
  }

  Future<void> _validarCompraNoBackend(PurchaseDetails compra) async {
    if (_validandoCompra) {
      // Não descartamos a transação que chegou enquanto outra validação
      // estava em curso. Ela fica disponível para nova tentativa manual.
      _compraPendenteValidacao = compra;
      return;
    }

    final user = _supabase.auth.currentUser;
    final session = _supabase.auth.currentSession;
    if (user == null || session == null) {
      _compraPendenteValidacao = compra;
      if (!mounted) return;
      setState(() {
        _iniciandoCompra = false;
        _validandoCompra = false;
        _erro = 'Sua sessão expirou. Entre novamente e toque em '
            '“Tentar validar compra pendente”. Não faça outra compra.';
        _mensagem = null;
      });
      return;
    }

    if (_serverBaseUrl.isEmpty ||
        widget.planoId.trim().isEmpty ||
        _productId.isEmpty) {
      _compraPendenteValidacao = compra;
      if (!mounted) return;
      setState(() {
        _iniciandoCompra = false;
        _validandoCompra = false;
        _erro = 'Faltam dados do checkout Apple. A transação foi preservada; '
            'corrija a configuração antes de tentar novamente.';
        _mensagem = null;
      });
      return;
    }

    final transactionId = compra.purchaseID?.trim() ?? '';
    if (transactionId.isEmpty) {
      _compraPendenteValidacao = compra;
      if (!mounted) return;
      setState(() {
        _iniciandoCompra = false;
        _validandoCompra = false;
        _erro = 'A Apple entregou a compra sem identificador de transação. '
            'A compra não será finalizada nem repetida automaticamente.';
        _mensagem = null;
      });
      return;
    }

    _validandoCompra = true;
    _compraPendenteValidacao = compra;
    if (mounted) {
      setState(() {
        _iniciandoCompra = false;
        _erro = null;
        _mensagem = 'Validando compra com a Apple...';
      });
    }

    try {
      final uri = Uri.parse('$_serverBaseUrl/apple/validar-compra');
      final payload = <String, dynamic>{
        'usuario_id': user.id,
        'plano_id': widget.planoId,
        'apple_product_id': compra.productID,
        'tipo_compra': _isSubscription ? 'recorrente' : 'avulso',
        'recorrente': _isSubscription,
        'transaction_id': transactionId,
        'transaction_date': compra.transactionDate,
        'verification_source': compra.verificationData.source,
        'verification_data': compra.verificationData.serverVerificationData,
        'local_verification_data':
            compra.verificationData.localVerificationData,
      };

      final response = await http
          .post(
            uri,
            headers: {
              'Content-Type': 'application/json',
              'Authorization': 'Bearer ${session.accessToken}',
            },
            body: jsonEncode(payload),
          )
          .timeout(const Duration(seconds: 45));

      Map<String, dynamic> data = <String, dynamic>{};
      if (response.body.trim().isNotEmpty) {
        final decoded = jsonDecode(response.body);
        if (decoded is Map) {
          data = Map<String, dynamic>.from(decoded);
        } else {
          throw FormatException(
            'O backend Apple retornou JSON inválido (HTTP ${response.statusCode}).',
          );
        }
      }

      if (response.statusCode < 200 || response.statusCode >= 300) {
        final detalhe = data['mensagem'] ??
            data['erro'] ??
            data['error'] ??
            data['message'] ??
            'HTTP ${response.statusCode}';
        throw Exception('Backend Apple: $detalhe');
      }

      // O servidor precisa afirmar explicitamente que validou a transação.
      final validado = data['success'] == true &&
          (data['validado'] == true ||
              data['purchase_valid'] == true ||
              data['assinatura_ativa'] == true);
      if (!validado) {
        final detalhe = data['mensagem'] ??
            data['erro'] ??
            data['error'] ??
            data['message'] ??
            'A Apple ainda não confirmou a compra no servidor.';
        throw Exception(detalhe.toString());
      }

      // Só finaliza a transação do StoreKit depois da confirmação do servidor.
      // Se a finalização local falhar, mantém a mesma PurchaseDetails para retry;
      // a rota do backend deve responder idempotentemente na próxima consulta.
      final finalizada = await _finalizarCompra(compra);
      if (!finalizada) {
        _compraPendenteValidacao = compra;
        if (mounted) {
          setState(() {
            _iniciandoCompra = false;
            _validandoCompra = false;
            _erro = 'A Apple confirmou o pagamento, mas o iPhone não conseguiu '
                'finalizar a transação local. Toque em “Tentar validar compra '
                'pendente”; não faça outra compra.';
            _mensagem = null;
          });
        }
        return;
      }

      _compraPendenteValidacao = null;
      _compraAguardandoApple = null;
      _bloqueioPorTransacaoDuplicada = false;
      if (!mounted) return;
      setState(() {
        _iniciandoCompra = false;
        _validandoCompra = false;
        _compraAprovada = true;
        _mensagem = 'Pagamento aprovado pela Apple!';
        _erro = null;
      });
      widget.onCompraAprovada?.call();
    } on TimeoutException {
      _compraPendenteValidacao = compra;
      if (!mounted) return;
      setState(() {
        _iniciandoCompra = false;
        _validandoCompra = false;
        _erro = 'O servidor Apple demorou para responder. A transação foi '
            'mantida para recuperação. Toque em “Tentar validar compra pendente”; '
            'não inicie outra compra.';
        _mensagem = null;
      });
      debugPrint(
          '[APPLE][VALIDACAO_TIMEOUT] produto=${compra.productID} transaction=$transactionId');
    } catch (e) {
      _compraPendenteValidacao = compra;
      if (!mounted) return;
      setState(() {
        _iniciandoCompra = false;
        _validandoCompra = false;
        _erro = e.toString().replaceFirst('Exception: ', '');
        _mensagem = 'A transação foi preservada. Corrija o problema e tente '
            'validá-la novamente, sem iniciar outra cobrança.';
      });
      debugPrint(
          '[APPLE][VALIDACAO_FALHOU] produto=${compra.productID} transaction=$transactionId erro=$e');
    } finally {
      _validandoCompra = false;
      if (mounted) setState(() {});
    }
  }

  Future<bool> _finalizarCompra(PurchaseDetails compra) async {
    if (!compra.pendingCompletePurchase) return true;
    try {
      await _iap.completePurchase(compra);
      debugPrint(
          '[APPLE][COMPRA_FINALIZADA] produto=${compra.productID} transaction=${compra.purchaseID ?? '-'}');
      return true;
    } catch (e) {
      debugPrint(
          '[APPLE][COMPLETE_PURCHASE_FALHOU] produto=${compra.productID} transaction=${compra.purchaseID ?? '-'} erro=$e');
      return false;
    }
  }

  Future<void> _restaurarCompras() async {
    if (!_isSubscription) {
      if (!mounted) return;
      setState(() {
        _mensagem = 'Compras avulsas consumíveis não são recuperadas pelo '
            'botão de restauração da Apple. A transação pendente deve ser '
            'recebida pelo purchaseStream e validada no servidor.';
        _erro = null;
      });
      return;
    }

    try {
      if (mounted) {
        setState(() {
          _erro = null;
          _mensagem = 'Procurando compras anteriores na Apple...';
        });
      }
      await _iap.restorePurchases();
    } catch (e) {
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
        title: const Text('App Store'),
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
                          child: const Icon(Icons.shopping_bag_outlined,
                              color: Colors.white, size: 34),
                        ),
                        const SizedBox(width: 14),
                        Expanded(
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Text(
                                'Pagar com Apple',
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
                                    color: Colors.white60, fontSize: 14),
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
                            fontSize: 15),
                      ),
                      const SizedBox(height: 12),
                      ...widget.beneficios.map(
                        (beneficio) => Padding(
                          padding: const EdgeInsets.only(bottom: 8),
                          child: Row(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              const Icon(Icons.check_circle_outline,
                                  color: Color(0xFF5CE1A3), size: 19),
                              const SizedBox(width: 9),
                              Expanded(
                                child: Text(
                                  beneficio,
                                  style: const TextStyle(
                                      color: Colors.white70, height: 1.3),
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
                          borderRadius: BorderRadius.circular(14)),
                      child: Column(
                        children: [
                          const Text(
                            'Preço pela App Store',
                            style:
                                TextStyle(color: Colors.white54, fontSize: 13),
                          ),
                          const SizedBox(height: 6),
                          if (_carregandoProduto)
                            const Padding(
                              padding: EdgeInsets.symmetric(vertical: 6),
                              child: CircularProgressIndicator(color: laranja),
                            )
                          else
                            Text(
                              _produtoSelecionado?.price ?? 'Indisponível',
                              style: const TextStyle(
                                  color: laranja,
                                  fontSize: 32,
                                  fontWeight: FontWeight.bold),
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
                              color: Colors.redAccent.withValues(alpha: 0.5)),
                        ),
                        child: Text(_erro!,
                            textAlign: TextAlign.center,
                            style: const TextStyle(color: Colors.redAccent)),
                      ),
                    ],
                    const SizedBox(height: 22),
                    ElevatedButton.icon(
                      onPressed: (!_appleDisponivel ||
                              _carregandoProduto ||
                              _produtoSelecionado == null ||
                              _iniciandoCompra ||
                              _validandoCompra ||
                              _compraAprovada ||
                              _compraAguardandoApple != null ||
                              (_bloqueioPorTransacaoDuplicada &&
                                  _compraPendenteValidacao == null))
                          ? null
                          : (_compraPendenteValidacao != null
                              ? _revalidarCompraPendente
                              : _comprarComApple),
                      style: ElevatedButton.styleFrom(
                        backgroundColor: laranja,
                        foregroundColor: Colors.white,
                        disabledBackgroundColor: Colors.white12,
                        padding: const EdgeInsets.symmetric(vertical: 16),
                        shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(14)),
                      ),
                      icon: (_iniciandoCompra || _validandoCompra)
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  strokeWidth: 2.3, color: Colors.white),
                            )
                          : Icon(_compraAprovada
                              ? Icons.check_circle
                              : Icons.shopping_cart_checkout),
                      label: Text(
                        _compraAprovada
                            ? 'COMPRA APROVADA'
                            : _validandoCompra
                                ? 'VALIDANDO COMPRA...'
                                : _compraPendenteValidacao != null
                                    ? 'TENTAR VALIDAR COMPRA PENDENTE'
                                    : _iniciandoCompra
                                        ? 'ABRINDO APP STORE...'
                                        : 'PAGAR COM APPLE',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                    ),
                    if (_compraPendenteValidacao != null) ...[
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed:
                            _validandoCompra ? null : _revalidarCompraPendente,
                        child: const Text(
                          'Tentar validar compra pendente',
                          style: TextStyle(color: Colors.white60),
                        ),
                      ),
                    ] else if (_bloqueioPorTransacaoDuplicada ||
                        _compraAguardandoApple != null) ...[
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: _validandoCompra
                            ? null
                            : _verificarTransacaoPendente,
                        child: const Text(
                          'Verificar transação pendente',
                          style: TextStyle(color: Colors.white60),
                        ),
                      ),
                    ] else if (_isSubscription) ...[
                      const SizedBox(height: 12),
                      TextButton(
                        onPressed: (_iniciandoCompra || _validandoCompra)
                            ? null
                            : _restaurarCompras,
                        child: const Text(
                          'Restaurar compra anterior',
                          style: TextStyle(color: Colors.white60),
                        ),
                      ),
                    ],
                    const SizedBox(height: 8),
                    const Text(
                      'O pagamento e a assinatura são processados pela Apple. '
                      'O Ache Obra libera o plano somente após o servidor confirmar a transação.',
                      textAlign: TextAlign.center,
                      style: TextStyle(
                          color: Colors.white38, fontSize: 11, height: 1.35),
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
