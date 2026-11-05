import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:printing/printing.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'lista_conversas_page.dart';

class PedidoMateriaisPage extends StatefulWidget {
  const PedidoMateriaisPage({super.key});

  @override
  State<PedidoMateriaisPage> createState() => _PedidoMateriaisPageState();
}

class _PedidoMateriaisPageState extends State<PedidoMateriaisPage> {
  final _tituloPedidoController = TextEditingController();
  List<Map<String, dynamic>> _itensPedido = [];
  List<String> _produtosCadastradosBanco = [];
  bool _carregandoProdutos = true;
  bool _isSalvandoPedido = false;
  List<Map<String, dynamic>> _meusPedidosSalvos = [];
  String? _idPedidoEmEdicao;

  final _produtoTempController = TextEditingController();
  final _quantidadeTempController = TextEditingController(text: '1');
  final _observacaoTempController = TextEditingController();
  bool _isManualTemp = false;

  final GlobalKey<FormFieldState> _autocompleteKey =
      GlobalKey<FormFieldState>();
  String? _fotoUrl;

  @override
  void initState() {
    super.initState();
    _carregarDadosIniciais();
  }

  Future<void> _carregarDadosIniciais() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user != null) {
      try {
        final data = await Supabase.instance.client
            .from('tab_usuarios')
            .select('foto_url')
            .eq('id', user.id)
            .single();
        setState(() {
          _fotoUrl = data['foto_url'];
        });
        await _carregarMeusPedidosSalvos(user.id);
      } catch (e) {
        debugPrint('Erro ao carregar dados: $e');
      }
    }
    await _carregarProdutosDoBanco();
  }

  Future<void> _carregarProdutosDoBanco() async {
    try {
      final data = await Supabase.instance.client
          .from('tab_produtos')
          .select('produto_nome')
          .order('produto_nome', ascending: true);

      setState(() {
        _produtosCadastradosBanco =
            (data as List).map((e) => e['produto_nome'].toString()).toList();
        _carregandoProdutos = false;
      });
    } catch (e) {
      setState(() => _carregandoProdutos = false);
    }
  }

  Future<void> _carregarMeusPedidosSalvos(String userId) async {
    try {
      final data = await Supabase.instance.client
          .from('tab_pedidos_materiais')
          .select()
          .or('usuario_id.eq.$userId,cliente_id.eq.$userId')
          .order('id', ascending: false);

      setState(() {
        _meusPedidosSalvos = List<Map<String, dynamic>>.from(data);
      });
    } catch (e) {
      debugPrint('Erro ao carregar pedidos: $e');
    }
  }

  void _adicionarItemPedido() {
    final prod = _produtoTempController.text.trim();
    final qtd = _quantidadeTempController.text.trim();
    final obs = _observacaoTempController.text.trim();

    if (prod.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Informe o nome do produto!"),
          backgroundColor: Colors.redAccent));
      return;
    }

    if (qtd.isEmpty || (int.tryParse(qtd) ?? 0) <= 0) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Informe uma quantidade válida!"),
          backgroundColor: Colors.redAccent));
      return;
    }

    setState(() {
      _itensPedido.add({
        'produto': prod,
        'quantidade': qtd,
        'observacao': obs.isNotEmpty ? obs : null,
      });
      _produtoTempController.clear();
      _autocompleteKey.currentState?.reset();
      _quantidadeTempController.text = '1';
      _observacaoTempController.clear();
    });
  }

  void _removerItemPedido(int index) {
    setState(() {
      _itensPedido.removeAt(index);
    });
  }

  Future<void> _gerarECompartilharPdf({
    required String titulo,
    required List<dynamic> itens,
    String? dataEmissao,
  }) async {
    final pdf = pw.Document();
    pw.ImageProvider? logoImage;

    try {
      final ByteData bytes = await rootBundle.load('assets/Logo_ache_obra.png');
      logoImage = pw.MemoryImage(bytes.buffer.asUint8List());
    } catch (e) {
      if (_fotoUrl != null && _fotoUrl!.trim().isNotEmpty) {
        try {
          logoImage = await networkImage(_fotoUrl!);
        } catch (_) {}
      }
    }

    String dataExibicao = dataEmissao != null
        ? dataEmissao
        : "${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}";

    pdf.addPage(
      pw.Page(
        pageFormat: PdfPageFormat.a4,
        build: (pw.Context context) {
          return pw.Column(
              crossAxisAlignment: pw.CrossAxisAlignment.start,
              children: [
                pw.Row(
                    mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                    children: [
                      pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text("PEDIDO DE MATERIAIS",
                                style: pw.TextStyle(
                                    fontSize: 20,
                                    fontWeight: pw.FontWeight.bold,
                                    color: PdfColors.orange900)),
                            pw.Text(titulo,
                                style: pw.TextStyle(
                                    fontSize: 14,
                                    fontWeight: pw.FontWeight.bold)),
                            pw.Text("Data de Emissão: $dataExibicao",
                                style: pw.TextStyle(
                                    fontSize: 11, color: PdfColors.grey700)),
                          ]),
                      if (logoImage != null)
                        pw.Container(
                            width: 50, height: 50, child: pw.Image(logoImage)),
                    ]),
                pw.Divider(color: PdfColors.grey400),
                ...itens.asMap().entries.map((entry) {
                  var it = entry.value;
                  return pw.Padding(
                      padding: const pw.EdgeInsets.only(bottom: 8),
                      child: pw.Column(
                          crossAxisAlignment: pw.CrossAxisAlignment.start,
                          children: [
                            pw.Text(
                                "${entry.key + 1}. ${it['produto']} - Qtd: ${it['quantidade']}",
                                style: pw.TextStyle(
                                    fontSize: 12,
                                    fontWeight: pw.FontWeight.bold)),
                            if (it['observacao'] != null &&
                                it['observacao'].toString().isNotEmpty)
                              pw.Padding(
                                  padding: const pw.EdgeInsets.only(left: 12),
                                  child: pw.Text("Obs: ${it['observacao']}",
                                      style: pw.TextStyle(
                                          fontSize: 10,
                                          fontStyle: pw.FontStyle.italic,
                                          color: PdfColors.grey700))),
                          ]));
                }),
              ]);
        },
      ),
    );

    await Printing.sharePdf(
        bytes: await pdf.save(), filename: 'pedido_materiais.pdf');
  }

  void _mostrarOpcoesCompartilhamento(Map<String, dynamic> pedido) {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1a2c42),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(16)),
      ),
      builder: (context) {
        return Padding(
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
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 12),
              const Center(
                child: Text(
                  "Compartilhar Pedido",
                  style: TextStyle(
                    color: Color(0xFFff9800),
                    fontSize: 18,
                    fontWeight: FontWeight.bold,
                  ),
                ),
              ),
              const SizedBox(height: 20),
              InkWell(
                onTap: () {
                  Navigator.pop(context);
                  _enviarPeloChatAcheObra(pedido);
                },
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF253c59),
                    borderRadius: BorderRadius.circular(12),
                    border:
                        Border.all(color: const Color(0xFFff9800), width: 1),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1a2c42),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.business,
                            color: Color(0xFFff9800), size: 24),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Enviar pelo Chat do Ache Obra",
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              "Ir direto para o chat",
                              style: TextStyle(
                                color: Colors.white54,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const Icon(Icons.arrow_forward, color: Color(0xFFff9800)),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 12),
              InkWell(
                onTap: () {
                  Navigator.pop(context);
                  _compartilharExternamente(pedido);
                },
                child: Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: const Color(0xFF253c59),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(color: Colors.white24, width: 1),
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(10),
                        decoration: BoxDecoration(
                          color: const Color(0xFF1a2c42),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: const Icon(Icons.share,
                            color: Colors.green, size: 24),
                      ),
                      const SizedBox(width: 12),
                      const Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(
                              "Compartilhar em outros apps",
                              style: TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                                fontSize: 14,
                              ),
                            ),
                            SizedBox(height: 2),
                            Text(
                              "WhatsApp, PDF, etc.",
                              style: TextStyle(
                                color: Colors.white54,
                                fontSize: 12,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 20),
            ],
          ),
        );
      },
    );
  }

  Future<void> _enviarPeloChatAcheObra(Map<String, dynamic> pedido) async {
    if (mounted) {
      Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) => ListaConversasPage(orcamentoParaEnviar: pedido),
        ),
      );
    }
  }

  Future<void> _compartilharExternamente(Map<String, dynamic> pedido) async {
    final titulo = pedido['titulo'] ?? 'PEDIDO DE MATERIAIS';
    final itens = pedido['itens'] as List<dynamic>? ?? [];

    await _gerarECompartilharPdf(
        titulo: titulo, itens: itens, dataEmissao: pedido['created_at']);

    String textoZap = "*PEDIDO DE MATERIAIS - ACHE OBRA*\n📌 *$titulo*\n\n";
    for (int i = 0; i < itens.length; i++) {
      textoZap +=
          "${i + 1}. ${itens[i]['produto']} - Qtd: ${itens[i]['quantidade']}\n";
      if (itens[i]['observacao'] != null &&
          itens[i]['observacao'].toString().isNotEmpty) {
        textoZap += "   💬 Obs: ${itens[i]['observacao']}\n";
      }
    }
    textoZap += "\nEnviado via aplicativo Ache Obra.";

    final url =
        Uri.parse('https://wa.me/?text=${Uri.encodeComponent(textoZap)}');
    if (await canLaunchUrl(url)) {
      await launchUrl(url, mode: LaunchMode.externalApplication);
    }
  }

  void _abrirFormularioEdicaoPedido(Map<String, dynamic> pedido) {
    setState(() {
      _idPedidoEmEdicao = pedido['id'].toString();
      _tituloPedidoController.text = pedido['titulo'] ?? '';
      _itensPedido = [];
      final itens = pedido['itens'] as List<dynamic>? ?? [];
      for (var it in itens) {
        _itensPedido.add({
          'produto': it['produto'] ?? '',
          'quantidade': it['quantidade']?.toString() ?? '1',
          'observacao': it['observacao']
        });
      }
    });
  }

  Future<void> _excluirPedidoSalvo(dynamic id) async {
    try {
      await Supabase.instance.client
          .from('tab_pedidos_materiais')
          .delete()
          .eq('id', id);
      final user = Supabase.instance.client.auth.currentUser;
      if (user != null) await _carregarMeusPedidosSalvos(user.id);
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Pedido excluído!"), backgroundColor: Colors.green));
    } catch (e) {
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("Erro: $e"), backgroundColor: Colors.redAccent));
    }
  }

  Future<void> _salvarEGerarPdf() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null ||
        _tituloPedidoController.text.trim().isEmpty ||
        _itensPedido.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
          content: Text("Preencha o título e adicione itens!"),
          backgroundColor: Colors.redAccent));
      return;
    }

    setState(() => _isSalvandoPedido = true);
    try {
      final dadosPedido = {
        'usuario_id': user.id,
        'cliente_id': user.id,
        'titulo': _tituloPedidoController.text.trim().toUpperCase(),
        'itens': _itensPedido,
      };

      if (_idPedidoEmEdicao != null) {
        await Supabase.instance.client
            .from('tab_pedidos_materiais')
            .update(dadosPedido)
            .eq('id', _idPedidoEmEdicao!);
      } else {
        await Supabase.instance.client
            .from('tab_pedidos_materiais')
            .insert(dadosPedido);
      }
      await _carregarMeusPedidosSalvos(user.id);

      final pedidoTemp = {
        'titulo': _tituloPedidoController.text.trim().toUpperCase(),
        'itens': List<Map<String, dynamic>>.from(_itensPedido),
        'created_at': DateTime.now().toIso8601String(),
      };

      setState(() {
        _tituloPedidoController.clear();
        _itensPedido.clear();
        _idPedidoEmEdicao = null;
        _isSalvandoPedido = false;
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(const SnackBar(
            content: Text("Pedido salvo com sucesso!"),
            backgroundColor: Colors.green));
        _mostrarOpcoesCompartilhamento(pedidoTemp);
      }
    } catch (e) {
      setState(() => _isSalvandoPedido = false);
      if (mounted)
        ScaffoldMessenger.of(context).showSnackBar(SnackBar(
            content: Text("Erro ao salvar: $e"),
            backgroundColor: Colors.redAccent));
    }
  }

  void _abrirModalMeusPedidosSalvos() {
    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF1a2c42),
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(16))),
      builder: (context) {
        return StatefulBuilder(builder: (context, setModalState) {
          return FractionallySizedBox(
            heightFactor: 0.85,
            child: Padding(
              padding: const EdgeInsets.all(12.0),
              child: Column(children: [
                Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text("Meus Pedidos Salvos",
                          style: TextStyle(
                              color: Color(0xFFff9800),
                              fontSize: 18,
                              fontWeight: FontWeight.bold)),
                      IconButton(
                          icon: const Icon(Icons.close, color: Colors.white),
                          onPressed: () => Navigator.pop(context)),
                    ]),
                const Divider(color: Colors.white24),
                Expanded(
                  child: ListView.builder(
                    itemCount: _meusPedidosSalvos.length,
                    itemBuilder: (context, index) {
                      final pedido = _meusPedidosSalvos[index];
                      final itens = pedido['itens'] as List<dynamic>? ?? [];
                      return Container(
                        margin: const EdgeInsets.symmetric(vertical: 6),
                        padding: const EdgeInsets.all(12),
                        decoration: BoxDecoration(
                            color: Colors.white12,
                            borderRadius: BorderRadius.circular(8)),
                        child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                  mainAxisAlignment:
                                      MainAxisAlignment.spaceBetween,
                                  children: [
                                    Expanded(
                                        child: Text(
                                            pedido['titulo'] ?? 'Sem Título',
                                            style: const TextStyle(
                                                color: Color(0xFFff9800),
                                                fontWeight: FontWeight.bold))),
                                    Row(
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          IconButton(
                                              icon: const Icon(Icons.share,
                                                  color: Color(0xFFff9800),
                                                  size: 20),
                                              onPressed: () =>
                                                  _mostrarOpcoesCompartilhamento(
                                                      pedido)),
                                          IconButton(
                                              icon: const Icon(Icons.edit,
                                                  color: Color(0xFFff9800),
                                                  size: 20),
                                              onPressed: () {
                                                Navigator.pop(context);
                                                _abrirFormularioEdicaoPedido(
                                                    pedido);
                                              }),
                                          IconButton(
                                              icon: const Icon(Icons.delete,
                                                  color: Colors.redAccent,
                                                  size: 20),
                                              onPressed: () async {
                                                await _excluirPedidoSalvo(
                                                    pedido['id']);
                                                setModalState(() {});
                                              }),
                                        ]),
                                  ]),
                              ...itens.map((it) => Text(
                                  "• ${it['produto']} (Qtd: ${it['quantidade']})",
                                  style: const TextStyle(
                                      color: Colors.white70, fontSize: 12))),
                            ]),
                      );
                    },
                  ),
                ),
              ]),
            ),
          );
        });
      },
    );
  }

  @override
  void dispose() {
    _tituloPedidoController.dispose();
    _produtoTempController.dispose();
    _quantidadeTempController.dispose();
    _observacaoTempController.dispose();
    super.dispose();
  }

  Widget _buildCard(String title, List<Widget> children) {
    return Container(
      width: double.infinity,
      padding: const EdgeInsets.all(12),
      decoration: BoxDecoration(
          color: const Color(0xFF253c59),
          borderRadius: BorderRadius.circular(8)),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(title,
            style: const TextStyle(
                color: Color(0xFFff9800),
                fontSize: 16,
                fontWeight: FontWeight.bold)),
        const Divider(color: Colors.white24),
        ...children,
      ]),
    );
  }

  Widget _buildEditableField(String label, TextEditingController controller,
      {TextCapitalization textCapitalization = TextCapitalization.none}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Column(crossAxisAlignment: CrossAxisAlignment.start, children: [
        Text(label,
            style: const TextStyle(color: Colors.white70, fontSize: 12)),
        const SizedBox(height: 2),
        TextField(
          controller: controller,
          textCapitalization: textCapitalization,
          style:
              const TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
          decoration: const InputDecoration(
              filled: true,
              fillColor: Colors.white12,
              border: OutlineInputBorder(),
              contentPadding:
                  EdgeInsets.symmetric(horizontal: 10, vertical: 8)),
        ),
      ]),
    );
  }

  @override
  Widget build(BuildContext context) {
    return SingleChildScrollView(
      padding: const EdgeInsets.all(12.0),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          _buildCard(
            _idPedidoEmEdicao == null
                ? "Novo Pedido de Materiais"
                : "Editar Pedido de Materiais",
            [
              _buildEditableField("Título do Pedido:", _tituloPedidoController,
                  textCapitalization: TextCapitalization.characters),
              const SizedBox(height: 8),
              const Text("ADICIONAR ITEM",
                  style: TextStyle(
                      color: Color(0xFFff9800),
                      fontSize: 13,
                      fontWeight: FontWeight.bold)),
              const Divider(color: Colors.white24),
              Row(children: [
                ChoiceChip(
                    label: const Text("Usar Lista",
                        style: TextStyle(fontSize: 11)),
                    selected: !_isManualTemp,
                    selectedColor: const Color(0xFFff9800),
                    backgroundColor: const Color(0xFF253c59),
                    side: const BorderSide(color: Colors.white, width: 1),
                    labelStyle: TextStyle(
                        color: !_isManualTemp ? Colors.black : Colors.white),
                    onSelected: (s) => setState(() => _isManualTemp = false)),
                const SizedBox(width: 8),
                ChoiceChip(
                    label: const Text("Digitar Manual",
                        style: TextStyle(fontSize: 11)),
                    selected: _isManualTemp,
                    selectedColor: const Color(0xFFff9800),
                    backgroundColor: const Color(0xFF253c59),
                    side: const BorderSide(color: Colors.white, width: 1),
                    labelStyle: TextStyle(
                        color: _isManualTemp ? Colors.black : Colors.white),
                    onSelected: (s) => setState(() => _isManualTemp = true)),
              ]),
              const SizedBox(height: 8),
              Row(children: [
                Expanded(
                    flex: 3,
                    child: _isManualTemp
                        ? TextField(
                            controller: _produtoTempController,
                            style: const TextStyle(
                                color: Colors.white,
                                fontWeight: FontWeight.bold),
                            decoration: const InputDecoration(
                                hintText: "Produto...",
                                hintStyle: TextStyle(color: Colors.white54),
                                filled: true,
                                fillColor: Colors.white12,
                                border: OutlineInputBorder(),
                                contentPadding: EdgeInsets.symmetric(
                                    horizontal: 10, vertical: 8)))
                        : Autocomplete<String>(
                            optionsBuilder: (v) =>
                                _produtosCadastradosBanco.where((o) => o
                                    .toLowerCase()
                                    .contains(v.text.toLowerCase())),
                            onSelected: (s) => _produtoTempController.text = s,
                            fieldViewBuilder: (c, ctrl, fn, onS) => TextField(
                                controller: ctrl,
                                focusNode: fn,
                                style: const TextStyle(
                                    color: Colors.white,
                                    fontWeight: FontWeight.bold),
                                decoration: const InputDecoration(
                                    hintText: "Selecione...",
                                    hintStyle: TextStyle(color: Colors.white54),
                                    filled: true,
                                    fillColor: Colors.white12,
                                    border: OutlineInputBorder(),
                                    contentPadding: EdgeInsets.symmetric(
                                        horizontal: 10, vertical: 8))))),
                const SizedBox(width: 6),
                Expanded(
                    flex: 1,
                    child: TextField(
                        controller: _quantidadeTempController,
                        keyboardType: TextInputType.number,
                        style: const TextStyle(
                            color: Colors.white, fontWeight: FontWeight.bold),
                        decoration: const InputDecoration(
                            labelText: "Qtd",
                            labelStyle: TextStyle(color: Colors.white70),
                            filled: true,
                            fillColor: Colors.white12,
                            border: OutlineInputBorder(),
                            contentPadding: EdgeInsets.symmetric(
                                horizontal: 10, vertical: 8)))),
              ]),
              const SizedBox(height: 6),
              TextField(
                  controller: _observacaoTempController,
                  style: const TextStyle(
                      color: Colors.white, fontWeight: FontWeight.bold),
                  decoration: const InputDecoration(
                      hintText: "Obs (opcional)",
                      hintStyle: TextStyle(color: Colors.white54),
                      filled: true,
                      fillColor: Colors.white12,
                      border: OutlineInputBorder(),
                      contentPadding:
                          EdgeInsets.symmetric(horizontal: 10, vertical: 8))),
              const SizedBox(height: 8),
              SizedBox(
                  width: double.infinity,
                  child: ElevatedButton.icon(
                      onPressed: _adicionarItemPedido,
                      style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFFff9800),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 12)),
                      icon: const Icon(Icons.add, size: 18),
                      label: const Text("Adicionar Item",
                          style: TextStyle(fontWeight: FontWeight.bold)))),
              const SizedBox(height: 10),
              ListView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: _itensPedido.length,
                  itemBuilder: (context, index) {
                    final item = _itensPedido[index];
                    return Container(
                        margin: const EdgeInsets.symmetric(vertical: 3),
                        padding: const EdgeInsets.symmetric(
                            horizontal: 8, vertical: 6),
                        decoration: BoxDecoration(
                            color: Colors.white12,
                            borderRadius: BorderRadius.circular(4)),
                        child: Row(children: [
                          Expanded(
                              child: Text(
                                  "${item['produto']} (Qtd: ${item['quantidade']})",
                                  style: const TextStyle(
                                      color: Colors.white, fontSize: 12))),
                          IconButton(
                              icon: const Icon(Icons.delete,
                                  color: Colors.red, size: 18),
                              onPressed: () => _removerItemPedido(index))
                        ]));
                  }),
              const SizedBox(height: 10),
              SizedBox(
                  width: double.infinity,
                  child: ElevatedButton(
                      onPressed: _isSalvandoPedido ? null : _salvarEGerarPdf,
                      style: ElevatedButton.styleFrom(
                          backgroundColor: const Color(0xFF4CAF50),
                          foregroundColor: Colors.white,
                          padding: const EdgeInsets.symmetric(vertical: 14)),
                      child: _isSalvandoPedido
                          ? const SizedBox(
                              width: 20,
                              height: 20,
                              child: CircularProgressIndicator(
                                  color: Colors.white, strokeWidth: 2))
                          : const Text("SALVAR E GERAR PDF",
                              style: TextStyle(
                                  fontWeight: FontWeight.bold, fontSize: 15)))),
            ],
          ),
          const SizedBox(height: 10),
          SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                  onPressed: _abrirModalMeusPedidosSalvos,
                  style: ElevatedButton.styleFrom(
                      backgroundColor: const Color(0xFF253c59),
                      foregroundColor: const Color(0xFFff9800),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                      side: const BorderSide(color: Color(0xFFff9800))),
                  icon: const Icon(Icons.list_alt, color: Color(0xFFff9800)),
                  label: const Text("MEUS PEDIDOS SALVOS",
                      style: TextStyle(
                          color: Color(0xFFff9800),
                          fontWeight: FontWeight.bold)))),
        ],
      ),
    );
  }
}
