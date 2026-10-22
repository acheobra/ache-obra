import 'dart:io';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:supabase_flutter/supabase_flutter.dart';
import 'package:share_plus/share_plus.dart';
import 'package:path_provider/path_provider.dart';
import 'package:pdf/pdf.dart';
import 'package:pdf/widgets.dart' as pw;
import 'orcamento_page.dart';
import 'lista_conversas_page.dart';

class ListaOrcamentosPage extends StatefulWidget {
  const ListaOrcamentosPage({super.key});

  @override
  State<ListaOrcamentosPage> createState() => _ListaOrcamentosPageState();
}

class _ListaOrcamentosPageState extends State<ListaOrcamentosPage> {
  List<Map<String, dynamic>> _orcamentos = [];
  bool _isLoading = true;

  @override
  void initState() {
    super.initState();
    _buscarOrcamentos();
  }

  // Função para gerar o PDF Profissional Completo para compartilhamento externo
  Future<void> _gerarECompartilharPdfExterno(Map<String, dynamic> orc) async {
    try {
      final pdf = pw.Document();

      // Carregar a logomarca
      pw.MemoryImage? imageLogo;
      try {
        final ByteData bytes =
            await rootBundle.load('assets/Logo_ache_obra.png');
        final Uint8List logoBytes = bytes.buffer.asUint8List();
        imageLogo = pw.MemoryImage(logoBytes);
      } catch (e) {
        debugPrint("Erro ao carregar a logo: $e");
      }

      final String cliNome = orc['cli_nome'] ?? 'Cliente';
      final String dataEmissao = orc['data_emissao'] ??
          "${DateTime.now().day}/${DateTime.now().month}/${DateTime.now().year}";
      final String validade = orc['validade'] ?? '10 dias';

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
                        pw.Text('Data: $dataEmissao',
                            style: const pw.TextStyle(fontSize: 12)),
                      ],
                    ),
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
                      '• Profissional: ${orc['prof_nome'] ?? ''} (${orc['prof_cpf_cnpj'] ?? ''})\nEndereço: ${orc['prof_endereco'] ?? ''} | Contato: ${orc['prof_contato'] ?? ''}'),
              pw.Paragraph(
                  text:
                      '• Cliente: $cliNome (${orc['cli_cpf'] ?? ''})\nTelefone: ${orc['cli_telefone'] ?? ''} | E-mail: ${orc['cli_email'] ?? ''}'),
              pw.Paragraph(
                  text:
                      '• Local da Obra: ${orc['local_obra'] ?? ''}\n• Validade da Proposta: $validade'),
              pw.SizedBox(height: 10),
              pw.Text('2. ESCOPO DO SERVIÇO',
                  style: pw.TextStyle(
                      fontSize: 13,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.blueGrey900)),
              pw.Divider(color: PdfColors.orange800),
              pw.Paragraph(
                  text:
                      '• Descrição Detalhada:\n${orc['descricao_servico'] ?? ''}'),
              pw.Paragraph(
                  text:
                      '• Quantitativos e Medidas: ${orc['quantitativos'] ?? ''}'),
              pw.Paragraph(text: '• Mão de Obra: ${orc['mao_de_obra'] ?? ''}'),
              pw.SizedBox(height: 10),
              pw.Text('3. CUSTOS E VALORES',
                  style: pw.TextStyle(
                      fontSize: 13,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.blueGrey900)),
              pw.Divider(color: PdfColors.orange800),
              pw.Paragraph(
                  text:
                      '• Modelo de Cobrança: ${orc['modelo_cobranca'] ?? ''}'),
              pw.Paragraph(
                  text: '• Valor Total/Unitário: ${orc['preco_total'] ?? ''}'),
              pw.Paragraph(text: '• Insumos Inclusos: ${orc['insumos'] ?? ''}'),
              pw.Paragraph(
                  text:
                      '• Responsabilidade dos Materiais:\n${orc['resp_materiais'] ?? ''}'),
              pw.SizedBox(height: 10),
              pw.Text('4. PRAZOS E CRONOGRAMA',
                  style: pw.TextStyle(
                      fontSize: 13,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.blueGrey900)),
              pw.Divider(color: PdfColors.orange800),
              pw.Paragraph(
                  text: '• Prazo de Execução: ${orc['prazo_execucao'] ?? ''}'),
              pw.Paragraph(
                  text:
                      '• Data Prevista de Início: ${orc['data_inicio'] ?? ''}'),
              pw.Paragraph(
                  text:
                      '• Observação Climática: ${orc['impacto_climatico'] ?? ''}'),
              pw.SizedBox(height: 10),
              pw.Text('5. CONDIÇÕES DE PAGAMENTO E TERMOS',
                  style: pw.TextStyle(
                      fontSize: 13,
                      fontWeight: pw.FontWeight.bold,
                      color: PdfColors.blueGrey900)),
              pw.Divider(color: PdfColors.orange800),
              pw.Paragraph(
                  text:
                      '• Forma de Pagamento: ${orc['forma_pagamento'] ?? ''}'),
              pw.Paragraph(
                  text:
                      '• Condições de Parcelamento: ${orc['parcelamento'] ?? ''}'),
              pw.Paragraph(
                  text:
                      '• Serviços Adicionais:\n${orc['servicos_adicionais'] ?? ''}'),
            ];
          },
        ),
      );

      final output = await getTemporaryDirectory();
      final file = File(
          "${output.path}/orcamento_${cliNome.replaceAll(' ', '_')}_${DateTime.now().millisecondsSinceEpoch}.pdf");
      await file.writeAsBytes(await pdf.save());

      await Share.shareXFiles(
        [XFile(file.path)],
        text: 'Segue o orçamento detalhado da obra.',
      );
    } catch (e) {
      debugPrint("Erro ao gerar PDF para compartilhamento externo: $e");
    }
  }

  void _mostrarOpcoesCompartilhamento(
      BuildContext context, Map<String, dynamic> orcamento) {
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

              // 1. OPÇÃO INTERNA (Envia o orçamento passando os dados para a ListaConversasPage)
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
                          orcamentoParaEnviar: orcamento,
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

              // 2. OPÇÃO EXTERNA (WhatsApp, E-mail, etc. - Gera o PDF completo)
              Material(
                color: const Color(0xFF253c59),
                borderRadius: BorderRadius.circular(15),
                child: InkWell(
                  borderRadius: BorderRadius.circular(15),
                  onTap: () async {
                    Navigator.pop(context); // Fecha o menu
                    await _gerarECompartilharPdfExterno(orcamento);
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
                                "WhatsApp, E-mail, etc. (PDF Completo)",
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

  Future<void> _buscarOrcamentos() async {
    setState(() => _isLoading = true);
    final user = Supabase.instance.client.auth.currentUser;
    if (user == null) {
      setState(() => _isLoading = false);
      return;
    }

    try {
      final response = await Supabase.instance.client
          .from('tab_orcamentos')
          .select()
          .eq('usuario_id', user.id)
          .order('id', ascending: false);

      setState(() {
        _orcamentos = List<Map<String, dynamic>>.from(response);
      });
    } catch (e) {
      debugPrint("Erro: $e");
    } finally {
      setState(() => _isLoading = false);
    }
  }

  Future<void> _excluirOrcamento(int id) async {
    bool confirm = await showDialog(
          context: context,
          builder: (context) => AlertDialog(
            backgroundColor: const Color(0xFF253c59),
            title: const Text("Excluir", style: TextStyle(color: Colors.white)),
            content: const Text(
              "Tem certeza?",
              style: TextStyle(color: Colors.white70),
            ),
            actions: [
              TextButton(
                onPressed: () => Navigator.pop(context, false),
                child: const Text(
                  "Cancelar",
                  style: TextStyle(color: Colors.white),
                ),
              ),
              TextButton(
                onPressed: () => Navigator.pop(context, true),
                child: const Text(
                  "Excluir",
                  style: TextStyle(color: Colors.redAccent),
                ),
              ),
            ],
          ),
        ) ??
        false;

    if (!confirm) return;

    try {
      await Supabase.instance.client
          .from('tab_orcamentos')
          .delete()
          .eq('id', id);
      _buscarOrcamentos();
    } catch (e) {
      debugPrint("Erro: $e");
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1a2c42),
      appBar: AppBar(
        title: const Text(
          "Meus Orçamentos",
          style: TextStyle(color: Colors.white),
        ),
        backgroundColor: const Color(0xFF101B2B),
        iconTheme: const IconThemeData(color: Color(0xFFff9800)),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh),
            onPressed: _buscarOrcamentos,
          ),
        ],
      ),
      body: _isLoading
          ? const Center(
              child: CircularProgressIndicator(color: Color(0xFFff9800)),
            )
          : _orcamentos.isEmpty
              ? const Center(
                  child: Text("Você ainda não tem orçamentos salvos.",
                      style: TextStyle(color: Colors.white70)),
                )
              : ListView.builder(
                  padding: const EdgeInsets.all(12),
                  itemCount: _orcamentos.length,
                  itemBuilder: (context, index) {
                    final orcamento = _orcamentos[index];
                    return Card(
                      color: const Color(0xFF253c59),
                      margin: const EdgeInsets.only(bottom: 12),
                      child: ListTile(
                        title: Text(
                          orcamento['cli_nome']?.isNotEmpty == true
                              ? "Cliente: ${orcamento['cli_nome']}"
                              : "Orçamento sem nome",
                          style: const TextStyle(
                            color: Colors.white,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                        subtitle: Text(
                          "Data: ${orcamento['data_emissao']} \nValor: ${orcamento['preco_total'] ?? '-'}",
                          style: const TextStyle(color: Colors.white70),
                        ),
                        trailing: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            IconButton(
                              icon: const Icon(
                                Icons.share,
                                color: Color(0xFFff9800),
                              ),
                              onPressed: () => _mostrarOpcoesCompartilhamento(
                                context,
                                orcamento,
                              ),
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.edit,
                                color: Colors.blueAccent,
                              ),
                              onPressed: () async {
                                await Navigator.push(
                                  context,
                                  MaterialPageRoute(
                                    builder: (context) => OrcamentoPage(
                                      orcamentoId: orcamento['id'],
                                    ),
                                  ),
                                );
                                _buscarOrcamentos();
                              },
                            ),
                            IconButton(
                              icon: const Icon(
                                Icons.delete,
                                color: Colors.redAccent,
                              ),
                              onPressed: () =>
                                  _excluirOrcamento(orcamento['id']),
                            ),
                          ],
                        ),
                      ),
                    );
                  },
                ),
      floatingActionButton: FloatingActionButton(
        backgroundColor: const Color(0xFFff9800),
        onPressed: () async {
          await Navigator.push(
            context,
            MaterialPageRoute(builder: (context) => const OrcamentoPage()),
          );
          _buscarOrcamentos();
        },
        child: const Icon(Icons.add, color: Colors.white),
      ),
    );
  }
}
