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
  bool _processandoAtualizacao = false;

  String? _erro;
  String? _mensagem;

  String get _serverBaseUrl =>
      widget.serverAppleUrl.trim().replaceAll(RegExp(r'/+$'), '');

  String get _productId => widget.appleProductId.trim();

  bool get _isSubscription => widget.recorrente;

  @override
  void initState() {
    super.initState();
    _purchaseSubscription = _iap.purchaseStream.listen(
      _processarAtualizacoesCompra,
      onDone: () => _purchaseSubscription?.cancel(),
      onError: (Object error) {
        if (!mounted) return;
        setState(() {
          _iniciandoCompra = false;
          _validandoCompra = false;
          _processandoAtualizacao = false;
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

    final produto = _produtoSelecionado;
    if (produto == null) {
      setState(() => _erro = 'O produto Apple ainda não foi carregado.');
      return;
    }

    final user = _supabase.auth.currentUser;
    if (user == null) {
      setState(
          () => _erro = 'Você precisa estar logado para realizar a compra.');
      return;
    }
    if (_serverBaseUrl.isEmpty) {
      setState(() =>
          _erro = 'O endereço do backend Apple ainda não foi configurado.');
      return;
    }

    try {
      setState(() {
        _iniciandoCompra = true;
        _erro = null;
        _mensagem = 'Abrindo a confirmação de compra da Apple...';
      });

      // A App Store apresenta a interface nativa de compra.
      final purchaseParam = PurchaseParam(
        productDetails: produto,
        applicationUserName: user.id,
      );

      // O produto avulso deve estar cadastrado como consumível na App Store
      // Connect se puder ser comprado novamente. Recorrência usa assinatura.
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
      setState(() {
        _iniciandoCompra = false;
        _mensagem = null;
        _erro = 'Não foi possível abrir a compra da Apple: $e';
      });
    }
  }

  Future<void> _processarAtualizacoesCompra(
    List<PurchaseDetails> compras,
  ) async {
    for (final compra in compras) {
      if (compra.productID != _productId) continue;

      switch (compra.status) {
        case PurchaseStatus.pending:
          if (!mounted) return;
          setState(() {
            _iniciandoCompra = false;
            _validandoCompra = false;
            _mensagem = 'A compra está pendente na App Store.';
            _erro = null;
          });
          break;
        case PurchaseStatus.purchased:
        case PurchaseStatus.restored:
          await _validarCompraNoBackend(compra);
          break;
        case PurchaseStatus.error:
          if (mounted) {
            setState(() {
              _iniciandoCompra = false;
              _validandoCompra = false;
              _mensagem = null;
              _erro = compra.error?.message ??
                  'A App Store informou um erro na compra.';
            });
          }
          if (compra.pendingCompletePurchase) await _finalizarCompra(compra);
          break;
        case PurchaseStatus.canceled:
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
  }

  Future<void> _validarCompraNoBackend(PurchaseDetails compra) async {
    if (_processandoAtualizacao || _validandoCompra) return;

    final user = _supabase.auth.currentUser;
    final session = _supabase.auth.currentSession;
    if (user == null || session == null) {
      if (!mounted) return;
      setState(() {
        _iniciandoCompra = false;
        _validandoCompra = false;
        _erro =
            'Sua sessão expirou. Entre novamente antes de validar a compra.';
        _mensagem = null;
      });
      return;
    }
    if (_serverBaseUrl.isEmpty) {
      if (!mounted) return;
      setState(() {
        _iniciandoCompra = false;
        _validandoCompra = false;
        _erro = 'O backend Apple ainda não foi configurado.';
        _mensagem = null;
      });
      return;
    }

    _processandoAtualizacao = true;
    try {
      if (mounted) {
        setState(() {
          _iniciandoCompra = false;
          _validandoCompra = true;
          _erro = null;
          _mensagem = 'Validando compra com a Apple...';
        });
      }

      final uri = Uri.parse('$_serverBaseUrl/apple/validar-compra');
      final payload = <String, dynamic>{
        'usuario_id': user.id,
        'plano_id': widget.planoId,
        'apple_product_id': compra.productID,
        'tipo_compra': _isSubscription ? 'recorrente' : 'avulso',
        'recorrente': _isSubscription,
        'transaction_id': compra.purchaseID,
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
        if (decoded is Map) data = Map<String, dynamic>.from(decoded);
      }
      if (response.statusCode < 200 || response.statusCode >= 300) {
        throw Exception(
          data['error'] ??
              data['message'] ??
              'Backend Apple retornou HTTP ${response.statusCode}.',
        );
      }

      // Nunca libera o plano com base apenas no status retornado pelo aparelho.
      final validado = data['success'] == true &&
          (data['validado'] == true ||
              data['purchase_valid'] == true ||
              data['assinatura_ativa'] == true);
      if (!validado) {
        throw Exception(
          data['error'] ??
              data['message'] ??
              'A compra ainda não foi confirmada pelo servidor Apple.',
        );
      }

      await _finalizarCompra(compra);
      if (!mounted) return;
      setState(() {
        _validandoCompra = false;
        _compraAprovada = true;
        _mensagem = 'Pagamento aprovado pela Apple!';
        _erro = null;
      });
      widget.onCompraAprovada?.call();
    } on TimeoutException {
      if (!mounted) return;
      setState(() {
        _validandoCompra = false;
        _erro = 'O servidor Apple demorou para responder. Não tente comprar '
            'novamente imediatamente. Abra esta tela novamente para recuperar a compra.';
        _mensagem = null;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() {
        _validandoCompra = false;
        _erro = e.toString().replaceFirst('Exception: ', '');
        _mensagem = null;
      });
      debugPrint('[APPLE] Falha na validação da compra: $e');
    } finally {
      _processandoAtualizacao = false;
    }
  }

  Future<void> _finalizarCompra(PurchaseDetails compra) async {
    if (!compra.pendingCompletePurchase) return;
    try {
      await _iap.completePurchase(compra);
    } catch (e) {
      debugPrint('[APPLE] Falha ao finalizar compra localmente: $e');
    }
  }

  Future<void> _restaurarCompras() async {
    try {
      setState(() {
        _erro = null;
        _mensagem = 'Procurando compras anteriores na Apple...';
      });
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
                              _compraAprovada)
                          ? null
                          : _comprarComApple,
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
                                : _iniciandoCompra
                                    ? 'ABRINDO APP STORE...'
                                    : 'PAGAR COM APPLE',
                        style: const TextStyle(
                            fontWeight: FontWeight.bold, fontSize: 15),
                      ),
                    ),
                    const SizedBox(height: 12),
                    TextButton(
                      onPressed: (_iniciandoCompra || _validandoCompra)
                          ? null
                          : _restaurarCompras,
                      child: const Text('Restaurar compra anterior',
                          style: TextStyle(color: Colors.white60)),
                    ),
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
