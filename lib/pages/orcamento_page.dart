import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart'; // Importante para carregar a imagem da logo
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'lista_conversas_page.dart'; // Importação necessária para o chat interno

class OrcamentoPage extends StatefulWidget {
  // Agora pode receber um ID se for para editar um orçamento existente
  final int? orcamentoId;

  const OrcamentoPage({super.key, this.orcamentoId});

  @override
  State<OrcamentoPage> createState() => _OrcamentoPageState();
}

class _OrcamentoPageState extends State<OrcamentoPage> {
  // Controladores - 1. Dados de Identificação
  final _profNomeCtrl = TextEditingController();
  final _profCpfCnpjCtrl = TextEditingController();
  final _profEnderecoCtrl = TextEditingController();
  final _profContatoCtrl = TextEditingController();

  final _cliNomeCtrl = TextEditingController();
  final _cliCpfCtrl = TextEditingController();
  final _cliTelefoneCtrl = TextEditingController();
  final _cliEmailCtrl = TextEditingController();

  final _localObraCtrl = TextEditingController();
  final _dataEmissaoCtrl = TextEditingController(
    text:
        "${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}",
  );
  final _validadeCtrl = TextEditingController(text: "10 dias");

  // Controladores - 2. Escopo do Serviço
  final _descricaoServicoCtrl = TextEditingController();
  final _quantitativosCtrl = TextEditingController();
  final _maoDeObraCtrl = TextEditingController(text: "Inclui ajudante");

  // Controladores - 3. Custos e Valores
  final _modeloCobrancaCtrl =
      TextEditingController(text: "Empreitada (Preço Fechado)");
  final _precoTotalCtrl = TextEditingController();
  final _insumosCtrl =
      TextEditingController(text: "Ferramentas básicas inclusas");
  final _respMateriaisCtrl = TextEditingController(
    text:
        "Os materiais de construção (cimento, tijolo, areia, etc.) correm por conta exclusiva do cliente.",
  );

  // Controladores - 4. Prazos e Cronograma
  final _prazoExecucaoCtrl = TextEditingController();
  final _dataInicioCtrl = TextEditingController();
  final _impactoClimaticoCtrl = TextEditingController(
    text: "Dias de chuva intensa poderão prorrogar o prazo de entrega.",
  );

  // Controladores - 5. Condições de Pagamento e Termos
  final _formaPagamentoCtrl = TextEditingController(text: "PIX ou Dinheiro");
  final _parcelamentoCtrl =
      TextEditingController(text: "50% de entrada e 50% na conclusão");
  final _servicosAdicionaisCtrl = TextEditingController(
    text:
        "Qualquer modificação ou serviço extra não listado gerará valor cobrado à parte.",
  );

  int? _orcamentoIdAtual;
  bool _isLoading = false;
  bool _isSalvo = false;
  bool _isSalvando = false;

  @override
  void initState() {
    super.initState();
    _orcamentoIdAtual = widget.orcamentoId;
    if (_orcamentoIdAtual != null) {
      _carregarOrcamentoExistente();
    }
  }

  Future<void> _carregarOrcamentoExistente() async {
    setState(() => _isLoading = true);
    try {
      final data = await Supabase.instance.client
          .from('tab_orcamentos')
          .select()
          .eq('id', _orcamentoIdAtual!)
          .single();

      setState(() {
        _profNomeCtrl.text = data['prof_nome'] ?? '';
        _profCpfCnpjCtrl.text = data['prof_cpf_cnpj'] ?? '';
        _profEnderecoCtrl.text = data['prof_endereco'] ?? '';
        _profContatoCtrl.text = data['prof_contato'] ?? '';
        _cliNomeCtrl.text = data['cli_nome'] ?? '';
        _cliCpfCtrl.text = data['cli_cpf'] ?? '';
        _cliTelefoneCtrl.text = data['cli_telefone'] ?? '';
        _cliEmailCtrl.text = data['cli_email'] ?? '';
        _localObraCtrl.text = data['local_obra'] ?? '';
        _dataEmissaoCtrl.text = data['data_emissao'] ?? _dataEmissaoCtrl.text;
        _validadeCtrl.text = data['validade'] ?? _validadeCtrl.text;
        _descricaoServicoCtrl.text = data['descricao_servico'] ?? '';
        _quantitativosCtrl.text = data['quantitativos'] ?? '';
        _maoDeObraCtrl.text = data['mao_de_obra'] ?? _maoDeObraCtrl.text;
        _modeloCobrancaCtrl.text =
            data['modelo_cobranca'] ?? _modeloCobrancaCtrl.text;
        _precoTotalCtrl.text = data['preco_total'] ?? '';
        _insumosCtrl.text = data['insumos'] ?? _insumosCtrl.text;
        _respMateriaisCtrl.text =
            data['resp_materiais'] ?? _respMateriaisCtrl.text;
        _prazoExecucaoCtrl.text = data['prazo_execucao'] ?? '';
        _dataInicioCtrl.text = data['data_inicio'] ?? '';
        _impactoClimaticoCtrl.text =
            data['impacto_climatico'] ?? _impactoClimaticoCtrl.text;
        _formaPagamentoCtrl.text =
            data['forma_pagamento'] ?? _formaPagamentoCtrl.text;
        _parcelamentoCtrl.text = data['parcelamento'] ?? _parcelamentoCtrl.text;
        _servicosAdicionaisCtrl.text =
            data['servicos_adicionais'] ?? _servicosAdicionaisCtrl.text;
        _isSalvo = true;
      });
    } catch (e) {
      debugPrint('Erro ao carregar orçamento: $e');
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _salvarOrcamento() async {
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
            content: Text("Usuário não autenticado."),
            backgroundColor: Colors.redAccent),
      );
      return;
    }

    setState(() => _isSalvando = true);

    try {
      final dados = {
        'usuario_id': user.id,
        'prof_nome': _profNomeCtrl.text.trim(),
        'prof_cpf_cnpj': _profCpfCnpjCtrl.text.trim(),
        'prof_endereco': _profEnderecoCtrl.text.trim(),
        'prof_contato': _profContatoCtrl.text.trim(),
        'cli_nome': _cliNomeCtrl.text.trim(),
        'cli_cpf': _cliCpfCtrl.text.trim(),
        'cli_telefone': _cliTelefoneCtrl.text.trim(),
        'cli_email': _cliEmailCtrl.text.trim(),
        'local_obra': _localObraCtrl.text.trim(),
        'data_emissao': _dataEmissaoCtrl.text.trim(),
        'validade': _validadeCtrl.text.trim(),
        'descricao_servico': _descricaoServicoCtrl.text.trim(),
        'quantitativos': _quantitativosCtrl.text.trim(),
        'mao_de_obra': _maoDeObraCtrl.text.trim(),
        'modelo_cobranca': _modeloCobrancaCtrl.text.trim(),
        'preco_total': _precoTotalCtrl.text.trim(),
        'insumos': _insumosCtrl.text.trim(),
        'resp_materiais': _respMateriaisCtrl.text.trim(),
        'prazo_execucao': _prazoExecucaoCtrl.text.trim(),
        'data_inicio': _dataInicioCtrl.text.trim(),
        'impacto_climatico': _impactoClimaticoCtrl.text.trim(),
        'forma_pagamento': _formaPagamentoCtrl.text.trim(),
        'parcelamento': _parcelamentoCtrl.text.trim(),
        'servicos_adicionais': _servicosAdicionaisCtrl.text.trim(),
      };

      if (_orcamentoIdAtual == null) {
        final response = await Supabase.instance.client
            .from('tab_orcamentos')
            .insert(dados)
            .select('id')
            .single();
        _orcamentoIdAtual = response['id'];
      } else {
        await Supabase.instance.client
            .from('tab_orcamentos')
            .update(dados)
            .eq('id', _orcamentoIdAtual!);
      }

      setState(() => _isSalvo = true);

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text("Orçamento salvo com sucesso!"),
            backgroundColor: Colors.green,
          ),
        );
      }
    } catch (e) {
      debugPrint('Erro ao salvar orçamento: $e');
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
              content: Text("Erro ao salvar: $e"),
              backgroundColor: Colors.redAccent),
        );
      }
    } finally {
      if (mounted) {
        setState(() => _isSalvando = false);
      }
    }
  }

  // Mapa de dados atual do formulário para envio unificado
  Map<String, dynamic> _obterDadosOrcamentoMap() {
    return {
      'id': _orcamentoIdAtual,
      'prof_nome': _profNomeCtrl.text,
      'prof_cpf_cnpj': _profCpfCnpjCtrl.text,
      'prof_endereco': _profEnderecoCtrl.text,
      'prof_contato': _profContatoCtrl.text,
      'cli_nome': _cliNomeCtrl.text,
      'cli_cpf': _cliCpfCtrl.text,
      'cli_telefone': _cliTelefoneCtrl.text,
      'cli_email': _cliEmailCtrl.text,
      'local_obra': _localObraCtrl.text,
      'data_emissao': _dataEmissaoCtrl.text,
      'validade': _validadeCtrl.text,
      'descricao_servico': _descricaoServicoCtrl.text,
      'quantitativos': _quantitativosCtrl.text,
      'mao_de_obra': _maoDeObraCtrl.text,
      'modelo_cobranca': _modeloCobrancaCtrl.text,
      'preco_total': _precoTotalCtrl.text,
      'insumos': _insumosCtrl.text,
      'resp_materiais': _respMateriaisCtrl.text,
      'prazo_execucao': _prazoExecucaoCtrl.text,
      'data_inicio': _dataInicioCtrl.text,
      'impacto_climatico': _impactoClimaticoCtrl.text,
      'forma_pagamento': _formaPagamentoCtrl.text,
      'parcelamento': _parcelamentoCtrl.text,
      'servicos_adicionais': _servicosAdicionaisCtrl.text,
    };
  }

  // Menu de Opções de Compartilhamento (Interno vs Externo)
  void _mostrarOpcoesCompartilhamento() {
    final orcamentoMap = _obterDadosOrcamentoMap();

    showModalBottomSheet(
      context: context,
      backgroundColor: const Color(0xFF101B2B),
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(25)),
      ),
      builder: (context) {
        return Padding(
          padding: const EdgeInsets.all(20.0),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 40,
                height: 4,
                margin: const EdgeInsets.only(bottom: 20),
                decoration: BoxDecoration(
                  color: Colors.white24,
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const Text(
                "Compartilhar Orçamento",
                style: TextStyle(
                  color: Colors.white,
                  fontSize: 18,
                  fontWeight: FontWeight.bold,
                ),
              ),
              const SizedBox(height: 20),

              // 1. OPÇÃO INTERNA (Envia pelo Chat do Ache Obra)
              Material(
                color: const Color(0xFF253c59),
                borderRadius: BorderRadius.circular(15),
                child: InkWell(
                  borderRadius: BorderRadius.circular(15),
                  onTap: () {
                    Navigator.pop(context); // Fecha o menu
                    Navigator.push(
                      context,
                      MaterialPageRoute(
                        builder: (context) => ListaConversasPage(
                          orcamentoParaEnviar: orcamentoMap,
                        ),
                      ),
                    );
                  },
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(
                          color: const Color(0xFFff9800), width: 1.5),
                    ),
                    child: Row(
                      children: [
                        ClipRRect(
                          borderRadius: BorderRadius.circular(8),
                          child: Image.asset(
                            'assets/Logo_ache_obra.png',
                            width: 40,
                            height: 40,
                            fit: BoxFit.cover,
                            errorBuilder: (c, o, s) => const Icon(
                              Icons.business,
                              color: Color(0xFFff9800),
                              size: 30,
                            ),
                          ),
                        ),
                        const SizedBox(width: 15),
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
                                "Escolher contato e enviar anexo PDF",
                                style: TextStyle(
                                    color: Colors.white70, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        const Icon(
                          Icons.arrow_forward,
                          color: Color(0xFFff9800),
                        ),
                      ],
                    ),
                  ),
                ),
              ),

              const SizedBox(height: 15),

              // 2. OPÇÃO EXTERNA (WhatsApp, E-mail, etc.)
              Material(
                color: const Color(0xFF253c59),
                borderRadius: BorderRadius.circular(15),
                child: InkWell(
                  borderRadius: BorderRadius.circular(15),
                  onTap: () async {
                    Navigator.pop(context); // Fecha o menu
                    await _gerarECompartilharPdfExterno();
                  },
                  child: Container(
                    padding: const EdgeInsets.all(12),
                    decoration: BoxDecoration(
                      borderRadius: BorderRadius.circular(15),
                      border: Border.all(color: Colors.white24, width: 1),
                    ),
                    child: const Row(
                      children: [
                        Icon(
                          Icons.share,
                          color: Colors.cyanAccent,
                          size: 30,
                        ),
                        SizedBox(width: 15),
                        Expanded(
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
                                "WhatsApp, E-mail, etc.",
                                style: TextStyle(
                                    color: Colors.white54, fontSize: 12),
                              ),
                            ],
                          ),
                        ),
                        Icon(
                          Icons.arrow_forward_ios,
                          color: Colors.white54,
                          size: 16,
                        ),
                      ],
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

  // Geração e Compartilhamento Externo original
  Future<void> _gerarECompartilharPdfExterno() async {
    final pdf = pw.Document();

    // 1. Carregar a logomarca
    pw.MemoryImage? imageLogo;
    try {
      final ByteData bytes = await rootBundle.load('assets/Logo_ache_obra.png');
      final Uint8List logoBytes = bytes.buffer.asUint8List();
      imageLogo = pw.MemoryImage(logoBytes);
    } catch (e) {
      debugPrint("Erro ao carregar a logo: $e");
    }

    pdf.addPage(
      pw.MultiPage(
        pageFormat: PdfPageFormat.a4,
        margin: const pw.EdgeInsets.all(32),
        build: (pw.Context context) {
          return [
            pw.Header(
              level: 0,
              child: pw.Row(
                mainAxisAlignment: pw.MainAxisAlignment.spaceBetween,
                crossAxisAlignment: pw.CrossAxisAlignment.start,
                children: [
                  pw.Column(
                    crossAxisAlignment: pw.CrossAxisAlignment.start,
                    children: [
                      pw.Text('ORÇAMENTO PROFISSIONAL',
                          style: pw.TextStyle(
                              fontSize: 18,
                              fontWeight: pw.FontWeight.bold,
                              color: PdfColors.orange800)),
                      pw.SizedBox(height: 5),
                      pw.Text('Data: ${_dataEmissaoCtrl.text}',
                          style: const pw.TextStyle(fontSize: 12)),
                    ],
                  ),
                  // 2. Inserir a logo no canto direito
                  if (imageLogo != null)
                    pw.Image(imageLogo, width: 80, height: 80)
                  else
                    pw.SizedBox(width: 80, height: 80),
                ],
              ),
            ),
            pw.SizedBox(height: 15),
            pw.Text('1. DADOS DE IDENTIFICAÇÃO',
                style: pw.TextStyle(
                    fontSize: 13,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.blueGrey900)),
            pw.Divider(color: PdfColors.orange800),
            pw.Paragraph(
                text:
                    '• Profissional: ${_profNomeCtrl.text} (CPF/CNPJ: ${_profCpfCnpjCtrl.text})\nEndereço: ${_profEnderecoCtrl.text} | Contato: ${_profContatoCtrl.text}'),
            pw.Paragraph(
                text:
                    '• Cliente: ${_cliNomeCtrl.text} (CPF: ${_cliCpfCtrl.text})\nTelefone: ${_cliTelefoneCtrl.text} | E-mail: ${_cliEmailCtrl.text}'),
            pw.Paragraph(
                text:
                    '• Local da Obra: ${_localObraCtrl.text}\n• Validade da Proposta: ${_validadeCtrl.text}'),
            pw.SizedBox(height: 10),
            pw.Text('2. ESCOPO DO SERVIÇO',
                style: pw.TextStyle(
                    fontSize: 13,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.blueGrey900)),
            pw.Divider(color: PdfColors.orange800),
            pw.Paragraph(
                text: '• Descrição Detalhada:\n${_descricaoServicoCtrl.text}'),
            pw.Paragraph(
                text: '• Quantitativos e Medidas: ${_quantitativosCtrl.text}'),
            pw.Paragraph(text: '• Mão de Obra: ${_maoDeObraCtrl.text}'),
            pw.SizedBox(height: 10),
            pw.Text('3. CUSTOS E VALORES',
                style: pw.TextStyle(
                    fontSize: 13,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.blueGrey900)),
            pw.Divider(color: PdfColors.orange800),
            pw.Paragraph(
                text: '• Modelo de Cobrança: ${_modeloCobrancaCtrl.text}'),
            pw.Paragraph(
                text: '• Valor Total/Unitário: ${_precoTotalCtrl.text}'),
            pw.Paragraph(text: '• Insumos Inclusos: ${_insumosCtrl.text}'),
            pw.Paragraph(
                text:
                    '• Responsabilidade dos Materiais:\n${_respMateriaisCtrl.text}'),
            pw.SizedBox(height: 10),
            pw.Text('4. PRAZOS E CRONOGRAMA',
                style: pw.TextStyle(
                    fontSize: 13,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.blueGrey900)),
            pw.Divider(color: PdfColors.orange800),
            pw.Paragraph(
                text: '• Prazo de Execução: ${_prazoExecucaoCtrl.text}'),
            pw.Paragraph(
                text: '• Data Prevista de Início: ${_dataInicioCtrl.text}'),
            pw.Paragraph(
                text: '• Observação Climática: ${_impactoClimaticoCtrl.text}'),
            pw.SizedBox(height: 10),
            pw.Text('5. CONDIÇÕES DE PAGAMENTO E TERMOS',
                style: pw.TextStyle(
                    fontSize: 13,
                    fontWeight: pw.FontWeight.bold,
                    color: PdfColors.blueGrey900)),
            pw.Divider(color: PdfColors.orange800),
            pw.Paragraph(
                text: '• Forma de Pagamento: ${_formaPagamentoCtrl.text}'),
            pw.Paragraph(
                text: '• Condições de Parcelamento: ${_parcelamentoCtrl.text}'),
            pw.Paragraph(
                text:
                    '• Serviços Adicionais:\n${_servicosAdicionaisCtrl.text}'),
          ];
        },
      ),
    );

    final output = await getTemporaryDirectory();
    final file = File(
        "${output.path}/orcamento_${DateTime.now().millisecondsSinceEpoch}.pdf");
    await file.writeAsBytes(await pdf.save());
    await Share.shareXFiles([XFile(file.path)],
        text: 'Segue o orçamento detalhado da obra.');
  }

  @override
  Widget build(BuildContext context) {
    if (_isLoading) {
      return const Scaffold(
          backgroundColor: Color(0xFF1a2c42),
          body: Center(
              child: CircularProgressIndicator(color: Color(0xFFff9800))));
    }
    return Scaffold(
      backgroundColor: const Color(0xFF1a2c42),
      appBar: AppBar(
        title: const Text("Elaborar Orçamento",
            style: TextStyle(color: Colors.white)),
        backgroundColor: const Color(0xFF101B2B),
        iconTheme: const IconThemeData(color: Color(0xFFff9800)),
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
                "Preencha os campos abaixo. Você pode editar e salvar as alterações a qualquer momento.",
                style: TextStyle(color: Colors.white70, fontSize: 13)),
            const SizedBox(height: 20),
            _buildSectionHeader("1. Dados de Identificação"),
            _buildTextField("Nome do Profissional", _profNomeCtrl),
            _buildTextField("CPF ou CNPJ", _profCpfCnpjCtrl),
            _buildTextField("Endereço do Profissional", _profEnderecoCtrl),
            _buildTextField("Contato (Telefone / E-mail)", _profContatoCtrl),
            const SizedBox(height: 10),
            _buildTextField("Nome Completo do Cliente", _cliNomeCtrl),
            _buildTextField("CPF do Cliente", _cliCpfCtrl),
            _buildTextField("Telefone do Cliente", _cliTelefoneCtrl),
            _buildTextField("E-mail do Cliente", _cliEmailCtrl),
            const SizedBox(height: 10),
            _buildTextField(
                "Local da Obra (Endereço Completo)", _localObraCtrl),
            _buildTextField("Data de Emissão", _dataEmissaoCtrl),
            _buildTextField("Validade do Orçamento", _validadeCtrl),
            const SizedBox(height: 20),
            _buildSectionHeader("2. Escopo do Serviço"),
            _buildTextField(
                "Descrição Detalhada (Passo a passo)", _descricaoServicoCtrl,
                maxLines: 4),
            _buildTextField("Quantitativos e Medidas (ex: 40 m² de parede)",
                _quantitativosCtrl),
            _buildTextField("Mão de Obra e Ajudante", _maoDeObraCtrl),
            const SizedBox(height: 20),
            _buildSectionHeader("3. Custos e Valores"),
            _buildTextField("Modelo de Cobrança (Empreitada, m², Diária)",
                _modeloCobrancaCtrl),
            _buildTextField("Preço Unitário e Total (R\$)", _precoTotalCtrl),
            _buildTextField(
                "Insumos Inclusos (Ferramentas, EPIs)", _insumosCtrl),
            _buildTextField("Responsabilidade de Materiais", _respMateriaisCtrl,
                maxLines: 3),
            const SizedBox(height: 20),
            _buildSectionHeader("4. Prazos e Cronograma"),
            _buildTextField(
                "Prazo de Execução (dias úteis / semanas)", _prazoExecucaoCtrl),
            _buildTextField("Data Prevista de Início", _dataInicioCtrl),
            _buildTextField(
                "Impacto Climático / Observações", _impactoClimaticoCtrl,
                maxLines: 2),
            const SizedBox(height: 20),
            _buildSectionHeader("5. Condições de Pagamento e Termos"),
            _buildTextField("Forma de Pagamento (PIX, Dinheiro, Cartão)",
                _formaPagamentoCtrl),
            _buildTextField("Parcelamento / Etapas", _parcelamentoCtrl),
            _buildTextField(
                "Serviços Adicionais (Cláusula Extra)", _servicosAdicionaisCtrl,
                maxLines: 3),
            const SizedBox(height: 30),
            SizedBox(
              width: double.infinity,
              child: ElevatedButton.icon(
                onPressed: _isSalvando ? null : _salvarOrcamento,
                style: ElevatedButton.styleFrom(
                    backgroundColor: const Color(0xFFff9800),
                    padding: const EdgeInsets.symmetric(vertical: 15)),
                icon: _isSalvando
                    ? const SizedBox(
                        height: 20,
                        width: 20,
                        child: CircularProgressIndicator(
                            color: Colors.white, strokeWidth: 2))
                    : const Icon(Icons.save, color: Colors.white),
                label: Text(
                    _orcamentoIdAtual == null
                        ? "SALVAR ORÇAMENTO"
                        : "ATUALIZAR ORÇAMENTO",
                    style: const TextStyle(
                        color: Colors.white, fontWeight: FontWeight.bold)),
              ),
            ),
            if (_isSalvo || _orcamentoIdAtual != null) ...[
              const SizedBox(height: 15),
              SizedBox(
                width: double.infinity,
                child: ElevatedButton.icon(
                  onPressed: _mostrarOpcoesCompartilhamento,
                  style: ElevatedButton.styleFrom(
                      backgroundColor: Colors.green,
                      padding: const EdgeInsets.symmetric(vertical: 15)),
                  icon: const Icon(Icons.share, color: Colors.white),
                  label: const Text("GERAR E COMPARTILHAR PDF",
                      style: TextStyle(
                          color: Colors.white, fontWeight: FontWeight.bold)),
                ),
              ),
            ],
            const SizedBox(height: 40),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
        padding: const EdgeInsets.only(bottom: 10, top: 10),
        child: Text(title,
            style: const TextStyle(
                color: Color(0xFFff9800),
                fontSize: 16,
                fontWeight: FontWeight.bold)));
  }

  Widget _buildTextField(String label, TextEditingController controller,
      {int maxLines = 1}) {
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 6),
      child: TextField(
        controller: controller,
        maxLines: maxLines,
        style: const TextStyle(color: Colors.white),
        decoration: InputDecoration(
          labelText: label,
          labelStyle: const TextStyle(color: Colors.white70, fontSize: 13),
          filled: true,
          fillColor: const Color(0xFF253c59),
          border: OutlineInputBorder(borderRadius: BorderRadius.circular(8)),
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 12),
        ),
      ),
    );
  }
}
