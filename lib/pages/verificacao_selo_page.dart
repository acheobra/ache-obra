import 'dart:io';

import 'package:flutter/foundation.dart';

import 'package:flutter/material.dart';

import 'package:image_picker/image_picker.dart';

import 'package:supabase_flutter/supabase_flutter.dart';

import 'package:in_app_purchase/in_app_purchase.dart';

import '../widgets/checkout_google.dart';

// EFÍPAY INATIVA (código preservado para futura reativação):

// import '../widgets/checkout_modal.dart';

// import '../services/servico_pagamento.dart';

class SeloVerificacaoPage extends StatefulWidget {
  const SeloVerificacaoPage({super.key});

  @override
  State<SeloVerificacaoPage> createState() => _SeloVerificacaoPageState();
}

class _SeloVerificacaoPageState extends State<SeloVerificacaoPage> {
  bool _carregando = true;

  bool _enviando = false;

  bool _selecionandoPagamento = false;

  static const String _googleBackendUrl =
      'https\://google-backend-e7ti.onrender.com';

  static const String _googleProductId = 'selo_verificacao_avulso';

  String _tipoPessoa = 'Fisica';

  String? _precoGoogleSelo;

  String _statusAtual = 'nao_verificado';

  String? _motivoRejeicao;

  String? _dataExpiracaoFormatada;
  DateTime? _dataExpiracao;
  bool _seloVencido = false;

  bool get _seloAtivo =>
      (_statusAtual == 'verificado' || _statusAtual == 'aprovado') &&
      !_seloVencido;

  bool get _solicitacaoEmAnalise => const {
        'enviado',
        'pendente',
        'em_analise',
        'em analise'
      }.contains(_statusAtual);

  // DADOS DINÂMICOS (com fallback caso o banco falhe)

  String _valorSelo = 'R\$ 49,90';

  double _valorNumerico = 49.90;

  String _validadeSelo = '1 Ano';

  String _prazoSelo = 'Até 48 horas';

  // ID real do registro em tab_planos_selos.

  // É enviado ao CheckoutModal/Render da mesma forma que o ID

  // do plano é enviado no fluxo de pagamento dos planos de usuário.

  String? _planoSeloId;

  File? _docFisicaFile;

  Uint8List? _docFisicaBytes;

  File? _docCnpjFile;

  Uint8List? _docCnpjBytes;

  File? _docSocioFile;

  Uint8List? _docSocioBytes;

  @override
  void initState() {
    super.initState();

    _carregarDadosEVerificarStatus();

    _carregarPrecoGoogleSelo();
  }

  /// Converte a data enviada pelo Supabase para o padrão brasileiro DD/MM/AAAA

  String? _formatarDataBR(dynamic dataRaw) {
    if (dataRaw == null) return null;

    try {
      final dt = DateTime.parse(dataRaw.toString()).toLocal();

      final dia = dt.day.toString().padLeft(2, '0');

      final mes = dt.month.toString().padLeft(2, '0');

      final ano = dt.year;

      return '$dia/$mes/$ano';
    } catch (_) {
      return dataRaw.toString();
    }
  }

  Future<void> _carregarDadosEVerificarStatus() async {
    final supabase = Supabase.instance.client;

    final user = supabase.auth.currentUser;

    // 1. Busca os valores atualizados da tabela tab_planos_selos

    try {
      final configResponse = await supabase
          .from('tab_planos_selos')
          .select()
          .order('id', ascending: false)
          .limit(1)
          .maybeSingle();

      if (configResponse != null && mounted) {
        setState(() {
          if (configResponse['id'] != null) {
            _planoSeloId = configResponse['id'].toString();
          }

          if (configResponse['valor'] != null) {
            final valRaw = configResponse['valor'];

            if (valRaw is num) {
              _valorNumerico = valRaw.toDouble();

              _valorSelo =
                  'R\$ ${_valorNumerico.toStringAsFixed(2).replaceAll('.', ',')}';
            } else {
              final strVal = valRaw.toString();

              final cleanStr = strVal
                  .replaceAll('R\$', '')
                  .replaceAll(' ', '')
                  .replaceAll(',', '.')
                  .trim();

              final parsed = double.tryParse(cleanStr);

              if (parsed != null && parsed > 0) {
                _valorNumerico = parsed;
              }

              _valorSelo = strVal.startsWith('R\$') ? strVal : 'R\$ $strVal';
            }
          }

          _validadeSelo =
              (configResponse['validade'] ?? _validadeSelo).toString();

          _prazoSelo =
              (configResponse['prazo_analise'] ?? _prazoSelo).toString();
        });
      }
    } catch (e) {
      debugPrint('Erro ao carregar dados da tabela tab_planos_selos: $e');
    }

    // 2. Verifica o status atual da solicitação do usuário e obtém a coluna data_expiracao

    try {
      if (user != null) {
        final response = await supabase
            .from('tab_selo_verificacao')
            .select()
            .eq('usuario_id', user.id)
            .maybeSingle();

        if (response != null && mounted) {
          final String statusBruto =
              (response['status'] ?? '').toString().trim().toLowerCase();

          // Leitura do campo data_expiracao recém criado no banco de dados

          final rawExp = response['data_expiracao'];

          // A data do banco é a fonte da verdade para renovação.
          // Sem data de expiração, não presumir vencimento.
          DateTime? exp;
          if (rawExp != null && rawExp.toString().trim().isNotEmpty) {
            exp = DateTime.tryParse(rawExp.toString());
          }
          final venceu =
              exp != null && !exp.toUtc().isAfter(DateTime.now().toUtc());

          setState(() {
            if (statusBruto.isEmpty ||
                statusBruto == 'nenhum' ||
                statusBruto == 'nao verificado' ||
                statusBruto == 'nao_verificado' ||
                statusBruto == 'não verificado') {
              _statusAtual = 'nao_verificado';
            } else {
              _statusAtual = statusBruto;
            }

            _motivoRejeicao = response['motivo_rejeicao']?.toString();

            _tipoPessoa = response['tipo_pessoa'] ?? 'Fisica';

            _dataExpiracaoFormatada = _formatarDataBR(rawExp);
          });
        } else if (mounted) {
          setState(() {
            _statusAtual = 'nao_verificado';
          });
        }
      }
    } catch (e) {
      debugPrint('Erro ao verificar status do selo: $e');

      if (mounted) {
        setState(() {
          _statusAtual = 'nao_verificado';
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

  Future<void> _selecionarDocumento({required int tipoDoc}) async {
    if (_seloAtivo ||
        _statusAtual == 'enviado' ||
        _statusAtual == 'pendente' ||
        _statusAtual == 'em_analise' ||
        _statusAtual == 'em analise') {
      return;
    }

    final picker = ImagePicker();

    final pickedFile = await picker.pickImage(
      source: ImageSource.gallery,
      imageQuality: 80,
    );

    if (pickedFile != null) {
      if (kIsWeb) {
        final bytes = await pickedFile.readAsBytes();

        setState(() {
          if (tipoDoc == 1) {
            _docFisicaBytes = bytes;

            _docFisicaFile = null;
          } else if (tipoDoc == 2) {
            _docCnpjBytes = bytes;

            _docCnpjFile = null;
          } else if (tipoDoc == 3) {
            _docSocioBytes = bytes;

            _docSocioFile = null;
          }
        });
      } else {
        final file = File(pickedFile.path);

        setState(() {
          if (tipoDoc == 1) {
            _docFisicaFile = file;

            _docFisicaBytes = null;
          } else if (tipoDoc == 2) {
            _docCnpjFile = file;

            _docCnpjBytes = null;
          } else if (tipoDoc == 3) {
            _docSocioFile = file;

            _docSocioBytes = null;
          }
        });
      }
    }
  }

  // ============================================================

  // EFÍPAY INATIVA - FLUXO ORIGINAL PRESERVADO ABAIXO

  // Para reativar futuramente, revisar antes as regras da loja.

  // Não há chamada ativa para estes métodos na versão Google Play.

  // ============================================================

  /*

  // ============================================================

  // ESCOLHA DO PAGAMENTO - MESMO PADRÃO VISUAL DOS PLANOS

  // ============================================================



  String _formatarPreco(double valor) =>

      valor.toStringAsFixed(2).replaceAll('.', ',');



  void _avisarPagamento(String mensagem) {

    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(

      SnackBar(content: Text(mensagem), backgroundColor: Colors.orange),

    );

  }



  Widget _opcaoPagamento({

    required IconData icone,

    required String titulo,

    required String subtitulo,

    required String preco,

    required VoidCallback? onTap,

    bool destaque = false,

    bool indisponivel = false,

  }) {

    const laranja = Color(0xFFFF8C00);

    return Material(

      color: Colors.transparent,

      child: InkWell(

        onTap: indisponivel ? null : onTap,

        borderRadius: BorderRadius.circular(14),

        child: Container(

          width: double.infinity,

          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),

          decoration: BoxDecoration(

            color: indisponivel

                ? Colors.white.withValues(alpha: 0.03)

                : const Color(0xFF1A2C42),

            borderRadius: BorderRadius.circular(14),

            border: Border.all(

              color: indisponivel

                  ? Colors.white12

                  : destaque

                      ? laranja

                      : Colors.white24,

              width: destaque ? 1.5 : 1,

            ),

          ),

          child: Row(

            children: [

              Container(

                width: 44,

                height: 44,

                decoration: BoxDecoration(

                  color: laranja.withValues(alpha: 0.13),

                  borderRadius: BorderRadius.circular(12),

                ),

                child:

                    Icon(icone, color: indisponivel ? Colors.white30 : laranja),

              ),

              const SizedBox(width: 12),

              Expanded(

                child: Column(

                  crossAxisAlignment: CrossAxisAlignment.start,

                  children: [

                    Text(titulo,

                        style: TextStyle(

                          color: indisponivel ? Colors.white38 : Colors.white,

                          fontSize: 15,

                          fontWeight: FontWeight.bold,

                        )),

                    const SizedBox(height: 3),

                    Text(subtitulo,

                        style: TextStyle(

                          color: indisponivel ? Colors.white24 : Colors.white60,

                          fontSize: 11,

                        )),

                  ],

                ),

              ),

              const SizedBox(width: 10),

              Flexible(

                child: Text(preco,

                    textAlign: TextAlign.end,

                    style: TextStyle(

                      color: indisponivel ? Colors.white30 : laranja,

                      fontSize: 15,

                      fontWeight: FontWeight.bold,

                    )),

              ),

              const SizedBox(width: 8),

              Icon(Icons.chevron_right,

                  color: indisponivel ? Colors.white24 : Colors.white54),

            ],

          ),

        ),

      ),

    );

  }



  Future<String?> _mostrarOpcoesPagamento({

    required String titulo,

    required String descricao,

    required List<Widget> opcoes,

  }) {

    return showModalBottomSheet<String>(

      context: context,

      backgroundColor: Colors.transparent,

      isScrollControlled: true,

      builder: (sheetContext) => SafeArea(

        child: Padding(

          padding: EdgeInsets.only(

            bottom: MediaQuery.of(sheetContext).viewInsets.bottom,

          ),

          child: Container(

            margin: const EdgeInsets.all(14),

            padding: const EdgeInsets.fromLTRB(18, 18, 18, 20),

            decoration: BoxDecoration(

              color: const Color(0xFF101B2B),

              borderRadius: BorderRadius.circular(20),

              border: Border.all(color: Colors.white12),

            ),

            child: Column(

              mainAxisSize: MainAxisSize.min,

              crossAxisAlignment: CrossAxisAlignment.start,

              children: [

                Row(children: [

                  Expanded(

                    child: Text(titulo,

                        style: const TextStyle(

                          color: Colors.white,

                          fontSize: 20,

                          fontWeight: FontWeight.bold,

                        )),

                  ),

                  IconButton(

                    onPressed: () => Navigator.pop(sheetContext),

                    icon: const Icon(Icons.close, color: Colors.white54),

                  ),

                ]),

                Text(descricao,

                    style:

                        const TextStyle(color: Colors.white60, fontSize: 12)),

                const SizedBox(height: 18),

                for (var i = 0; i < opcoes.length; i++) ...[

                  if (i > 0) const SizedBox(height: 12),

                  opcoes[i],

                ],

              ],

            ),

          ),

        ),

      ),

    );

  }



  Future<String?> _escolherFormaPagamento() {

    final preco = 'R\$ ${_formatarPreco(_valorNumerico)}';

    return _mostrarOpcoesPagamento(

      titulo: 'Como deseja pagar?',

      descricao: 'Escolha a forma de pagamento. O processo é rápido e seguro.',

      opcoes: [

        _opcaoPagamento(

          icone: Icons.pix,

          titulo: 'PIX',

          subtitulo: 'Pagamento avulso pela EfíPay',

          preco: preco,

          destaque: true,

          onTap: () => Navigator.pop(context, 'pix'),

        ),

        _opcaoPagamento(

          icone: Icons.credit_card,

          titulo: 'Cartão',

          subtitulo: 'Escolha EfíPay ou Google Play',

          preco: 'a partir de $preco',

          onTap: () => Navigator.pop(context, 'cartao'),

        ),

      ],

    );

  }



  Future<String?> _buscarPrecoGoogle() async {

    try {

      if (kIsWeb || !Platform.isAndroid) return null;

      final iap = InAppPurchase.instance;

      if (!await iap.isAvailable()) return null;

      final resposta = await iap.queryProductDetails({_googleProductId});

      if (resposta.error != null || resposta.productDetails.isEmpty) {

        return null;

      }

      for (final produto in resposta.productDetails) {

        if (produto.id == _googleProductId) return produto.price;

      }

    } catch (e) {

      debugPrint('[SELO][GOOGLE] Falha ao consultar preço: $e');

    }

    return null;

  }



  Future<String?> _escolherGatewayCartao() async {

    final precoGoogle = await _buscarPrecoGoogle();

    if (!mounted) return null;

    final precoEfi = 'R\$ ${_formatarPreco(_valorNumerico)}';

    return _mostrarOpcoesPagamento(

      titulo: 'Pague com cartão',

      descricao: 'Escolha por onde deseja concluir o pagamento.',

      opcoes: [

        _opcaoPagamento(

          icone: Icons.account_balance_wallet_outlined,

          titulo: 'EfíPay',

          subtitulo: 'Pagamento por cartão pela EfíPay',

          preco: precoEfi,

          destaque: true,

          onTap: () => Navigator.pop(context, 'efi'),

        ),

        _opcaoPagamento(

          icone: Icons.play_circle_outline,

          titulo: 'Google Play',

          subtitulo: 'Pagamento pela Google Play',

          preco: precoGoogle ?? 'A configurar',

          indisponivel: precoGoogle == null,

          onTap: () => Navigator.pop(context, 'google'),

        ),

      ],

    );

  }



  Future<bool> _abrirCheckoutEfi(String metodo) async {

    if (!mounted) return false;

    final resultado = await showDialog<bool>(

      context: context,

      barrierDismissible: false,

      builder: (dialogContext) => CheckoutModal(

        origemTipo: 'selo_verificacao',

        origemId: _planoSeloId!,

        ehRecorrente: false,

        valor: _valorNumerico,

        descricao: 'Selo de Verificação de Perfil',

        metodoPagamentoFixo: metodo,

      ),

    );

    return resultado == true;

  }



  Future<bool> _abrirCheckoutGoogle() async {

    if (!mounted) return false;

    // O checkout compartilhado envia plano_id para /google/validar-compra.

    // O backend PRECISA reconhecer selo_verificacao_avulso e mapear esse

    // identificador para tab_planos_selos, sem ativar um plano de assinatura.

    // Sem essa adaptação no server_google, a compra NÃO estará integrada.

    final resultado = await Navigator.of(context).push<bool>(

      MaterialPageRoute<bool>(

        builder: (pageContext) => CheckoutGooglePage(

          planoId: _planoSeloId!,

          nomePlano: 'Selo de Verificação',

          googleProductId: _googleProductId,

          googleBasePlanId: '',

          serverGoogleUrl: _googleBackendUrl,

          onCompraAprovada: () {

            if (Navigator.of(pageContext).canPop()) {

              Navigator.of(pageContext).pop(true);

            }

          },

        ),

      ),

    );

    return resultado == true;

  }



  Future<bool> _processarPagamentoSelo() async {

    final forma = await _escolherFormaPagamento();

    if (!mounted || forma == null) return false;

    if (forma == 'pix') return _abrirCheckoutEfi('pix');

    if (forma != 'cartao') return false;

    final gateway = await _escolherGatewayCartao();

    if (!mounted || gateway == null) return false;

    if (gateway == 'efi') return _abrirCheckoutEfi('cartao');

    if (gateway == 'google') return _abrirCheckoutGoogle();

    return false;

  }



  */

  // ============================================================

  // GOOGLE PLAY BILLING - ÚNICO CHECKOUT ATIVO PARA O SELO

  // ============================================================

  void _avisarPagamento(String mensagem) {
    if (!mounted) return;

    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(content: Text(mensagem), backgroundColor: Colors.orange),
    );
  }

  Future<void> _carregarPrecoGoogleSelo() async {
    try {
      if (kIsWeb || !Platform.isAndroid) return;

      final iap = InAppPurchase.instance;

      if (!await iap.isAvailable()) return;

      final resposta = await iap.queryProductDetails({_googleProductId});

      if (resposta.error != null) {
        debugPrint(
            '[SELO][GOOGLE] Erro ao consultar produto: ${resposta.error}');

        return;
      }

      for (final produto in resposta.productDetails) {
        if (produto.id == _googleProductId) {
          if (mounted) setState(() => _precoGoogleSelo = produto.price);

          return;
        }
      }
    } catch (e) {
      debugPrint('[SELO][GOOGLE] Falha ao consultar preço: $e');
    }
  }

  Future<bool> _abrirCheckoutGoogle() async {
    if (!mounted || _planoSeloId == null || _planoSeloId!.isEmpty) {
      return false;
    }

    // O backend deve reconhecer selo_verificacao_avulso e mapear

    // planoId para tab_planos_selos, sem ativar plano de assinatura.

    final resultado = await Navigator.of(context).push<bool>(
      MaterialPageRoute<bool>(
        builder: (pageContext) => CheckoutGooglePage(
          planoId: _planoSeloId!,
          nomePlano: 'Selo de Verificação',
          googleProductId: _googleProductId,
          googleBasePlanId: '',
          serverGoogleUrl: _googleBackendUrl,
          onCompraAprovada: () {
            if (Navigator.of(pageContext).canPop()) {
              Navigator.of(pageContext).pop(true);
            }
          },
        ),
      ),
    );

    return resultado == true;
  }

  Future<bool> _processarPagamentoSelo() async {
    // Não apresentar EfíPay, Pix ou seleção de gateway.

    if (kIsWeb || !Platform.isAndroid) {
      _avisarPagamento('Pagamento disponível pela Google Play no Android.');

      return false;
    }

    return _abrirCheckoutGoogle();
  }

  Future<void> _enviarSolicitacao() async {
    if (_selecionandoPagamento ||
        _enviando ||
        _seloAtivo ||
        _statusAtual == 'enviado' ||
        _statusAtual == 'pendente' ||
        _statusAtual == 'em_analise' ||
        _statusAtual == 'em analise') {
      return;
    }

    // 1. Validação dos documentos antes de abrir o pagamento

    if (_tipoPessoa == 'Fisica') {
      if (_docFisicaFile == null && _docFisicaBytes == null) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text('Por favor, envie a CNH ou RG contendo o CPF.'),
            backgroundColor: Colors.orange,
          ),
        );

        return;
      }
    } else {
      if ((_docCnpjFile == null && _docCnpjBytes == null) ||
          (_docSocioFile == null && _docSocioBytes == null)) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
                'Por favor, envie ambos os documentos para Pessoa Jurídica.'),
            backgroundColor: Colors.orange,
          ),
        );

        return;
      }
    }

    // O pagamento é iniciado somente após a validação dos documentos.

    if (_planoSeloId == null || _planoSeloId!.isEmpty) {
      _avisarPagamento(
          'Não foi possível carregar a configuração do selo. Tente novamente.');

      return;
    }

    setState(() => _selecionandoPagamento = true);

    bool pagamentoAprovado = false;

    try {
      pagamentoAprovado = await _processarPagamentoSelo();
    } catch (e) {
      debugPrint('[SELO] Falha ao abrir checkout: $e');

      _avisarPagamento(
          'Não foi possível concluir o pagamento. Tente novamente.');
    } finally {
      if (mounted) setState(() => _selecionandoPagamento = false);
    }

    if (!mounted || !pagamentoAprovado) return;

    // 3. Processamento e Envio após Pagamento Aprovado

    setState(() => _enviando = true);

    try {
      final supabase = Supabase.instance.client;

      final user = supabase.auth.currentUser;

      if (user == null) throw "Usuário não autenticado.";

      // Garante que o usuário autenticado também exista na tab_usuarios.

      // Esse vínculo é essencial para que o Admin consiga localizar o cadastro

      // completo a partir de tab_selo_verificacao.usuario_id.

      final usuarioBanco = await supabase
          .from('tab_usuarios')
          .select('id')
          .eq('id', user.id)
          .maybeSingle();

      if (usuarioBanco == null) {
        throw "Usuário autenticado não encontrado na tabela tab_usuarios.";
      }

      String? urlDoc1;

      String? urlDoc2;

      if (_tipoPessoa == 'Fisica') {
        final fileName =
            'doc_pf_${user.id}_${DateTime.now().millisecondsSinceEpoch}.jpg';

        final path = 'documentos/$fileName';

        if (kIsWeb) {
          await supabase.storage.from('documentos_verificacao').uploadBinary(
                path,
                _docFisicaBytes!,
                fileOptions: const FileOptions(upsert: true),
              );
        } else {
          await supabase.storage.from('documentos_verificacao').upload(
                path,
                _docFisicaFile!,
                fileOptions: const FileOptions(upsert: true),
              );
        }

        urlDoc1 = path;
      } else {
        final fileNameCnpj =
            'doc_cnpj_${user.id}_${DateTime.now().millisecondsSinceEpoch}.jpg';

        final pathCnpj = 'documentos/$fileNameCnpj';

        if (kIsWeb) {
          await supabase.storage.from('documentos_verificacao').uploadBinary(
                pathCnpj,
                _docCnpjBytes!,
                fileOptions: const FileOptions(upsert: true),
              );
        } else {
          await supabase.storage.from('documentos_verificacao').upload(
                pathCnpj,
                _docCnpjFile!,
                fileOptions: const FileOptions(upsert: true),
              );
        }

        urlDoc1 = pathCnpj;

        final fileNameSocio =
            'doc_socio_${user.id}_${DateTime.now().millisecondsSinceEpoch}.jpg';

        final pathSocio = 'documentos/$fileNameSocio';

        if (kIsWeb) {
          await supabase.storage.from('documentos_verificacao').uploadBinary(
                pathSocio,
                _docSocioBytes!,
                fileOptions: const FileOptions(upsert: true),
              );
        } else {
          await supabase.storage.from('documentos_verificacao').upload(
                pathSocio,
                _docSocioFile!,
                fileOptions: const FileOptions(upsert: true),
              );
        }

        urlDoc2 = pathSocio;
      }

      // Gravando o status como 'enviado' no banco de dados

      await supabase.from('tab_selo_verificacao').upsert({
        'usuario_id': user.id,
        'tipo_pessoa': _tipoPessoa,
        'documento_url': urlDoc1,
        'documento_url_2': urlDoc2,
        'status': 'enviado',
        'updated_at': DateTime.now().toIso8601String(),
      }, onConflict: 'usuario_id');

      setState(() {
        _statusAtual = 'enviado';
      });

      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('Pagamento e documentação enviados com sucesso!'),
          backgroundColor: Colors.green,
        ),
      );
    } catch (e) {
      if (!mounted) return;

      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('Erro ao finalizar solicitação: $e'),
          backgroundColor: Colors.red,
        ),
      );
    } finally {
      if (mounted) setState(() => _enviando = false);
    }
  }

  Widget _buildCardInformacoesSelo() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.symmetric(vertical: 16, horizontal: 12),
      margin: const EdgeInsets.only(bottom: 20),
      decoration: BoxDecoration(
        color: const Color(0xFF101B2B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: const Color(0xFFFF8C00),
          width: 1.5,
        ),
        boxShadow: const [
          BoxShadow(
            color: Colors.black26,
            blurRadius: 8,
            offset: Offset(0, 4),
          )
        ],
      ),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.spaceEvenly,
        children: [
          Expanded(
            child: Column(
              children: [
                const Icon(Icons.sell_outlined,
                    color: Color(0xFFFF8C00), size: 20),
                const SizedBox(height: 4),
                const Text('Investimento',
                    style: TextStyle(color: Colors.white54, fontSize: 11)),
                const SizedBox(height: 4),
                Text(
                  _valorSelo,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Color(0xFFFF8C00),
                    fontWeight: FontWeight.bold,
                    fontSize: 16,
                  ),
                ),
              ],
            ),
          ),
          Container(height: 40, width: 1, color: Colors.white12),
          Expanded(
            child: Column(
              children: [
                const Icon(Icons.event_available_outlined,
                    color: Colors.blueAccent, size: 20),
                const SizedBox(height: 4),
                const Text('Validade',
                    style: TextStyle(color: Colors.white54, fontSize: 11)),
                const SizedBox(height: 4),
                Text(
                  _validadeSelo,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 15,
                  ),
                ),
              ],
            ),
          ),
          Container(height: 40, width: 1, color: Colors.white12),
          Expanded(
            child: Column(
              children: [
                const Icon(Icons.timer_outlined,
                    color: Colors.greenAccent, size: 20),
                const SizedBox(height: 4),
                const Text('Prazo Análise',
                    style: TextStyle(color: Colors.white54, fontSize: 11)),
                const SizedBox(height: 4),
                Text(
                  _prazoSelo,
                  textAlign: TextAlign.center,
                  style: const TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildStatusButton() {
    String texto = 'IR PARA O PAGAMENTO';

    Color corBotao = const Color(0xFFFF8C00);

    IconData icone = Icons.payment;

    VoidCallback? onPressed =
        (_enviando || _selecionandoPagamento) ? null : _enviarSolicitacao;

    switch (_seloVencido ? 'vencido' : _statusAtual) {
      case 'pendente':
      case 'enviado':
        texto = 'SOLICITAÇÃO ENVIADA';

        corBotao = Colors.blue.shade700;

        icone = Icons.hourglass_top;

        onPressed = null;

        break;

      case 'em_analise':
      case 'em analise':
        texto = 'DOCUMENTAÇÃO EM ANÁLISE';

        corBotao = Colors.purple.shade700;

        icone = Icons.manage_search;

        onPressed = null;

        break;

      case 'vencido':
        texto = 'RENOVAR SELO DE VERIFICAÇÃO';
        corBotao = const Color(0xFFFF8C00);
        icone = Icons.autorenew;
        onPressed =
            (_enviando || _selecionandoPagamento) ? null : _enviarSolicitacao;
        break;

      case 'rejeitado':
        texto = 'REJEITADO (Toque para reenviar)';

        corBotao = Colors.red.shade700;

        icone = Icons.error_outline;

        onPressed =
            (_enviando || _selecionandoPagamento) ? null : _enviarSolicitacao;

        break;

      case 'verificado':
      case 'aprovado':
        texto = 'SEU PERFIL JÁ É VERIFICADO';

        corBotao = Colors.green.shade700;

        icone = Icons.verified;

        onPressed = null;

        break;

      case 'nao_verificado':
      default:
        texto = 'IR PARA O PAGAMENTO';

        corBotao = const Color(0xFFFF8C00);

        icone = Icons.payment;

        onPressed =
            (_enviando || _selecionandoPagamento) ? null : _enviarSolicitacao;
    }

    return SizedBox(
      width: double.infinity,
      child: ElevatedButton.icon(
        style: ElevatedButton.styleFrom(
          backgroundColor: corBotao,
          padding: const EdgeInsets.symmetric(vertical: 16),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
        ),
        onPressed: onPressed,
        icon: (_enviando || _selecionandoPagamento)
            ? const SizedBox(
                height: 20,
                width: 20,
                child: CircularProgressIndicator(
                    color: Colors.white, strokeWidth: 2),
              )
            : Icon(icone, color: Colors.white),
        label: Text(
          texto,
          style: const TextStyle(
            color: Colors.white,
            fontWeight: FontWeight.bold,
            fontSize: 15,
          ),
        ),
      ),
    );
  }

  Widget _buildStatusHeaderBadge() {
    Color cor = Colors.orange;

    String texto = 'NÃO VERIFICADO';

    IconData icone = Icons.info_outline;

    if (_seloVencido) {
      cor = Colors.orange;
      texto = 'SELO VENCIDO';
      icone = Icons.event_busy;
    } else if (_seloAtivo) {
      cor = Colors.green;

      texto = 'VERIFICADO';

      icone = Icons.verified;
    } else if (_statusAtual == 'enviado' || _statusAtual == 'pendente') {
      cor = Colors.blue;

      texto = 'ENVIADO / PENDENTE';

      icone = Icons.hourglass_top;
    } else if (_statusAtual == 'em_analise' || _statusAtual == 'em analise') {
      cor = Colors.purple;

      texto = 'EM ANÁLISE';

      icone = Icons.manage_search;
    } else if (_statusAtual == 'rejeitado') {
      cor = Colors.red;

      texto = 'REJEITADO';

      icone = Icons.error_outline;
    }

    return Center(
      child: Container(
        margin: const EdgeInsets.only(bottom: 16),
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
        decoration: BoxDecoration(
          color: cor.withValues(alpha: 0.15),
          borderRadius: BorderRadius.circular(20),
          border: Border.all(color: cor),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icone, color: cor, size: 18),
            const SizedBox(width: 8),
            Text(
              'Status: $texto',
              style: TextStyle(
                color: cor,
                fontWeight: FontWeight.bold,
                fontSize: 13,
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildVerificadoCard() {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: const Color(0xFF101B2B),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: Colors.green.shade400, width: 2),
      ),
      child: Column(
        children: [
          const Icon(Icons.verified, color: Colors.blue, size: 70),
          const SizedBox(height: 16),
          const Text(
            'Perfil Verificado!',
            style: TextStyle(
              color: Colors.white,
              fontSize: 22,
              fontWeight: FontWeight.bold,
            ),
          ),
          const SizedBox(height: 8),
          const Text(
            'Sua documentação foi analisada e aprovada com sucesso. O selo de verificação está ativo no seu perfil.',
            textAlign: TextAlign.center,
            style: TextStyle(color: Colors.white70, fontSize: 14, height: 1.4),
          ),
          if (_dataExpiracaoFormatada != null) ...[
            const SizedBox(height: 18),
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              decoration: BoxDecoration(
                color: Colors.greenAccent.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(20),
                border: Border.all(
                  color: Colors.greenAccent.withValues(alpha: 0.4),
                ),
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Icon(Icons.event_available,
                      color: Colors.greenAccent, size: 18),
                  const SizedBox(width: 8),
                  Text(
                    'Válido até: $_dataExpiracaoFormatada',
                    style: const TextStyle(
                      color: Colors.greenAccent,
                      fontWeight: FontWeight.bold,
                      fontSize: 13,
                    ),
                  ),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    if (_carregando) {
      return Scaffold(
        backgroundColor: const Color(0xFF1A2C42),
        appBar: AppBar(
          backgroundColor: const Color(0xFF101B2B),
          title: const Text('Selo de Verificação',
              style: TextStyle(color: Colors.white)),
          iconTheme: const IconThemeData(color: Colors.white),
        ),
        body: const Center(
          child: CircularProgressIndicator(color: Color(0xFFFF8C00)),
        ),
      );
    }

    final bool eVerificado = _seloAtivo;

    return Scaffold(
      backgroundColor: const Color(0xFF1A2C42),
      appBar: AppBar(
        backgroundColor: const Color(0xFF101B2B),
        title: const Text(
          'Selo de Verificação',
          style: TextStyle(
              color: Colors.white, fontSize: 18, fontWeight: FontWeight.bold),
        ),
        iconTheme: const IconThemeData(color: Colors.white),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(20.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _buildStatusHeaderBadge(),
            if (_seloVencido) ...[
              Container(
                width: double.infinity,
                margin: const EdgeInsets.only(bottom: 16),
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: Colors.orange.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(color: Colors.orange),
                ),
                child: Text(
                  'Seu selo venceu${_dataExpiracaoFormatada == null ? '' : ' em $_dataExpiracaoFormatada'}. '
                  'Para renovar, anexe os documentos e realize um novo pagamento pela Google Play. '
                  'A renovação será enviada para análise.',
                  style: const TextStyle(color: Colors.white, fontSize: 13),
                ),
              ),
            ],

            // CARD COM INFORMAÇÕES DINÂMICAS VINDAS DA TABELA TAB_PLANOS_SELOS

            _buildCardInformacoesSelo(),

            if (eVerificado) ...[
              _buildVerificadoCard(),
              const SizedBox(height: 30),
              _buildStatusButton(),
            ] else ...[
              const Center(
                child: Icon(Icons.verified, color: Colors.blue, size: 56),
              ),
              const SizedBox(height: 12),
              Center(
                child: Text(
                  _seloVencido
                      ? 'Renove seu Selo de Verificação'
                      : 'Obtenha seu Selo de Verificação',
                  style: TextStyle(
                    color: Color(0xFFFF8C00),
                    fontSize: 20,
                    fontWeight: FontWeight.bold,
                  ),
                  textAlign: TextAlign.center,
                ),
              ),
              const SizedBox(height: 8),
              const Text(
                'O selo de verificação confirma a autenticidade do seu perfil ou empresa na plataforma, gerando mais confiança para seus clientes e parceiros.',
                style:
                    TextStyle(color: Colors.white70, fontSize: 13, height: 1.4),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: 20),
              const Text(
                '📋 Requisitos de Documentação:',
                style: TextStyle(
                  color: Color(0xFFFF8C00),
                  fontSize: 16,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 8),
              Container(
                padding: const EdgeInsets.all(14),
                decoration: BoxDecoration(
                  color: const Color(0xFF101B2B),
                  borderRadius: BorderRadius.circular(10),
                  border: Border.all(color: Colors.white12),
                ),
                child: const Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      '👤 Pessoa Física:',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14),
                    ),
                    SizedBox(height: 2),
                    Text(
                      '• CNH ou RG que contenha CPF.',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                    SizedBox(height: 10),
                    Text(
                      '🏢 Pessoa Jurídica:',
                      style: TextStyle(
                          color: Colors.white,
                          fontWeight: FontWeight.bold,
                          fontSize: 14),
                    ),
                    SizedBox(height: 2),
                    Text(
                      '• Comprovante de CNPJ ativo atualizado e CNH ou RG com foto de CPF do titular ou sócio responsável.',
                      style: TextStyle(color: Colors.white70, fontSize: 13),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 20),
              const Text(
                'Selecione o Tipo de Perfil:',
                style: TextStyle(
                    color: Colors.white,
                    fontWeight: FontWeight.bold,
                    fontSize: 14),
              ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: RadioListTile<String>(
                      title: const Text('Pessoa Física',
                          style: TextStyle(color: Colors.white, fontSize: 13)),
                      value: 'Fisica',
                      groupValue: _tipoPessoa,
                      activeColor: const Color(0xFFFF8C00),
                      onChanged: (_statusAtual == 'enviado' ||
                              _statusAtual == 'pendente' ||
                              _statusAtual == 'em_analise' ||
                              _statusAtual == 'em analise')
                          ? null
                          : (val) => setState(() => _tipoPessoa = val!),
                    ),
                  ),
                  Expanded(
                    child: RadioListTile<String>(
                      title: const Text('Pessoa Jurídica',
                          style: TextStyle(color: Colors.white, fontSize: 13)),
                      value: 'Juridica',
                      groupValue: _tipoPessoa,
                      activeColor: const Color(0xFFFF8C00),
                      onChanged: (_statusAtual == 'enviado' ||
                              _statusAtual == 'pendente' ||
                              _statusAtual == 'em_analise' ||
                              _statusAtual == 'em analise')
                          ? null
                          : (val) => setState(() => _tipoPessoa = val!),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              if (_tipoPessoa == 'Fisica') ...[
                const Text(
                  'Documento (CNH ou RG que contenha CPF):',
                  style: TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                _buildImagePickerBox(
                  label: 'Anexar aqui CNH ou RG contendo CPF',
                  bytes: _docFisicaBytes,
                  file: _docFisicaFile,
                  onTap: () => _selecionarDocumento(tipoDoc: 1),
                ),
              ] else ...[
                const Text(
                  '1. Comprovante de Inscrição do CNPJ Atualizado:',
                  style: TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                _buildImagePickerBox(
                  label: 'Anexar aqui Cartão CNPJ atualizado',
                  bytes: _docCnpjBytes,
                  file: _docCnpjFile,
                  onTap: () => _selecionarDocumento(tipoDoc: 2),
                ),
                const SizedBox(height: 16),
                const Text(
                  '2. Documento com foto e CPF do titular ou sócio responsável:',
                  style: TextStyle(
                      color: Colors.white70,
                      fontSize: 13,
                      fontWeight: FontWeight.bold),
                ),
                const SizedBox(height: 8),
                _buildImagePickerBox(
                  label:
                      'Anexar aqui CNH ou RG com CPF do titular da empresa ou sócio responsável',
                  bytes: _docSocioBytes,
                  file: _docSocioFile,
                  onTap: () => _selecionarDocumento(tipoDoc: 3),
                ),
              ],
              if (_motivoRejeicao != null && _statusAtual == 'rejeitado') ...[
                const SizedBox(height: 16),
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: Colors.red.withValues(alpha: 0.2),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(color: Colors.redAccent),
                  ),
                  child: Text(
                    'Motivo da Rejeição: $_motivoRejeicao',
                    style:
                        const TextStyle(color: Colors.redAccent, fontSize: 13),
                  ),
                ),
              ],
              const SizedBox(height: 30),
              _buildStatusButton(),
            ],

            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildImagePickerBox({
    required String label,
    Uint8List? bytes,
    File? file,
    required VoidCallback onTap,
  }) {
    bool podeAlterar = !_solicitacaoEmAnalise && !_seloAtivo;

    return GestureDetector(
      onTap: podeAlterar ? onTap : null,
      child: Container(
        width: double.infinity,
        height: 140,
        decoration: BoxDecoration(
          color: const Color(0xFF253c59),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: const Color(0xFFFF8C00), width: 1.5),
        ),
        child: bytes != null
            ? ClipRRect(
                borderRadius: BorderRadius.circular(11),
                child: Image.memory(bytes, fit: BoxFit.cover),
              )
            : file != null
                ? ClipRRect(
                    borderRadius: BorderRadius.circular(11),
                    child: Image.file(file, fit: BoxFit.cover),
                  )
                : Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      const Icon(Icons.add_a_photo,
                          color: Color(0xFFFF8C00), size: 36),
                      const SizedBox(height: 8),
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16.0),
                        child: Text(
                          label,
                          style: const TextStyle(
                              color: Colors.white70,
                              fontSize: 13,
                              fontWeight: FontWeight.bold),
                          textAlign: TextAlign.center,
                        ),
                      ),
                    ],
                  ),
      ),
    );
  }
}
