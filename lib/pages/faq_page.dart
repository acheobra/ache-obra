import 'package:flutter/material.dart';

// Modelo para cada item do FAQ
class FaqItem {
  final String categoria;
  final String pergunta;
  final String resposta;

  FaqItem({
    required this.categoria,
    required this.pergunta,
    required this.resposta,
  });
}

class FaqPage extends StatefulWidget {
  const FaqPage({super.key});

  @override
  State<FaqPage> createState() => _FaqPageState();
}

class _FaqPageState extends State<FaqPage> {
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  // Lista de Perguntas e Respostas do FAQ
  final List<FaqItem> _todosOsFaqs = [
    // 1. Sobre o Aplicativo e Cadastro
    FaqItem(
      categoria: '1. Sobre o Aplicativo e Cadastro',
      pergunta: 'O que é o Ache Obra?',
      resposta:
          'O Ache Obra é a plataforma que conecta clientes a profissionais, pedreiros, arquitetos e engenheiros qualificados para construções e reformas em todo o Brasil.',
    ),
    FaqItem(
      categoria: '1. Sobre o Aplicativo e Cadastro',
      pergunta: 'Quais são os tipos de conta disponíveis?',
      resposta:
          'Oferecemos perfis dedicados para Clientes (que buscam profissionais/serviços) e perfis profissionais para Profissionais da Obra, Arquitetos e Engenheiros (que desejam divulgar seus serviços).',
    ),
    FaqItem(
      categoria: '1. Sobre o Aplicativo e Cadastro',
      pergunta:
          'Posso me cadastrar com mais de um tipo de usuário na mesma conta?',
      resposta:
          'Não. Cada conta permite o cadastro de apenas um perfil de usuário (ex: se você se cadastrar como Cliente, não poderá usar a mesma conta para se cadastrar como Profissional da Obra, Arquiteto ou Engenheiro).',
    ),
    FaqItem(
      categoria: '1. Sobre o Aplicativo e Cadastro',
      pergunta:
          'Posso alterar ou migrar meu tipo de conta (ex: de Cliente para Profissional)?',
      resposta:
          'Não é possível fazer a migração direta do tipo de perfil em uma conta existente. Caso deseje alterar seu tipo de usuário, você deverá excluir sua conta atual e realizar um novo cadastro no formato desejado.\n\nAtenção: ao excluir a conta, você perderá permanentemente todos os seus dados, fotos e o histórico da conta anterior.',
    ),
    FaqItem(
      categoria: '1. Sobre o Aplicativo e Cadastro',
      pergunta:
          'Posso utilizar o mesmo CPF ou CNPJ para criar mais de uma conta?',
      resposta:
          'Não. Para garantir a segurança da plataforma, não é permitido cadastrar CPFs ou CNPJs repetidos. Cada documento é único e só pode estar vinculado a uma única conta no sistema.',
    ),
    FaqItem(
      categoria: '1. Sobre o Aplicativo e Cadastro',
      pergunta: 'Como altero meus dados de perfil ou contato?',
      resposta:
          'Acesse o menu "Meu Perfil" no app para editar seu nome, telefone, e-mail e fotos de trabalhos anteriores.',
    ),

    // 2. Selo de Verificação
    FaqItem(
      categoria: '2. Selo de Verificação',
      pergunta: 'O que é o Selo de Verificação e por que ativá-lo?',
      resposta:
          'O Selo de Verificação comprova a autenticidade do seu perfil ou empresa. Perfis com o selo transmitem mais confiança aos clientes e ganham prioridade de visibilidade nas buscas.',
    ),
    FaqItem(
      categoria: '2. Selo de Verificação',
      pergunta: 'Quais documentos preciso enviar para solicitar o Selo?',
      resposta:
          '• Pessoa Física: Foto legível de documento oficial com foto (RG ou CNH).\n• Pessoa Jurídica (CNPJ): Comprovante de CNPJ e documento com foto do sócio responsável.',
    ),
    FaqItem(
      categoria: '2. Selo de Verificação',
      pergunta: 'Qual o prazo de análise da documentação?',
      resposta:
          'A análise da equipe leva em média até 3 dias úteis. Você receberá uma notificação assim que o processo for concluído.',
    ),
    FaqItem(
      categoria: '2. Selo de Verificação',
      pergunta: 'O que acontece se minha solicitação for rejeitada?',
      resposta:
          'Caso o documento esteja ilegível ou desatualizado, o pedido será rejeitado. Você poderá enviar uma nova documentação diretamente pela aba do Selo de Verificação.',
    ),
    FaqItem(
      categoria: '2. Selo de Verificação',
      pergunta: 'Qual é a validade do Selo de Verificação?',
      resposta:
          'O selo possui validade anual (365 dias) a partir da data de aprovação, devendo ser renovado após esse período.',
    ),

    // 3. Planos e Publicações
    FaqItem(
      categoria: '3. Planos e Publicações',
      pergunta:
          'Como funcionam os planos para Profissionais, Arquitetos e Engenheiros?',
      resposta:
          'Disponibilizamos planos que variam do Grátis até opções avançadas (Alicerce/Base/Croqui, Mestre/Carga/Conceito e Topo/Estrutural/Masterplan), cada um com limites específicos de postagens, fotos e vídeos.',
    ),
    FaqItem(
      categoria: '3. Planos e Publicações',
      pergunta:
          'Qual a diferença entre contratar um plano Avulso e Recorrente?',
      resposta:
          'O plano Avulso garante benefícios por um período fixo (ex: 30 dias). O plano Recorrente oferece acesso estendido (ex: 365 dias) com valores promocionais e renovação simplificada.',
    ),
    FaqItem(
      categoria: '3. Planos e Publicações',
      pergunta: 'O que significa ter "Destaque nas Buscas"?',
      resposta:
          'Perfis com a opção de Destaque aparecem nos primeiros lugares da lista de pesquisa da sua região, aumentando drasticamente as chances de fechar novos orçamentos.',
    ),

    // 4. Campanhas e Premiações
    FaqItem(
      categoria: '4. Campanhas e Premiações',
      pergunta: 'Como funcionam as campanhas de premiação no app?',
      resposta:
          'O Ache Obra realiza campanhas periódicas com prêmios e incentivos para os usuários ativos na plataforma.',
    ),
    FaqItem(
      categoria: '4. Campanhas e Premiações',
      pergunta: 'Quem pode participar das campanhas?',
      resposta:
          'Todos os usuários cadastrados e ativos que cumprirem as regras específicas de cada campanha divulgada no aplicativo.',
    ),
    FaqItem(
      categoria: '4. Campanhas e Premiações',
      pergunta: 'Como sei se uma campanha está disponível na minha região?',
      resposta:
          'As campanhas podem ser de alcance Nacional, por Estado ou específicas para determinadas Cidades. As informações de abrangência e período de vigência ficam visíveis no banner da própria campanha.',
    ),

    // 5. Pagamentos e Segurança
    FaqItem(
      categoria: '5. Pagamentos e Segurança',
      pergunta: 'Quais são as formas de pagamento aceitas no aplicativo?',
      resposta:
          'Processamos pagamentos com segurança via PagBank, aceitando Pix (com liberação imediata) e Cartão de Crédito.',
    ),
    FaqItem(
      categoria: '5. Pagamentos e Segurança',
      pergunta: 'Minhas informações financeiras estão seguras?',
      resposta:
          'Sim. Todos os dados de pagamento são criptografados e processados diretamente pelo gateway do PagBank; não armazenamos dados de cartão no aplicativo.',
    ),

    // 6. Suporte e Atendimento
    FaqItem(
      categoria: '6. Suporte e Atendimento',
      pergunta: 'Como posso entrar em contato com a equipe de suporte?',
      resposta:
          'Se você não encontrou a resposta para sua dúvida ou precisa de ajuda com sua conta, envie um e-mail para suporte@acheobra.com.br. Nossa equipe analisará sua solicitação e responderá o mais breve possível.',
    ),
  ];

  // Filtra as perguntas com base na busca
  List<FaqItem> get _faqsFiltrados {
    if (_searchQuery.isEmpty) return _todosOsFaqs;
    final query = _searchQuery.toLowerCase();
    return _todosOsFaqs.where((item) {
      return item.pergunta.toLowerCase().contains(query) ||
          item.resposta.toLowerCase().contains(query) ||
          item.categoria.toLowerCase().contains(query);
    }).toList();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    // Agrupa a lista filtrada por categoria
    final Map<String, List<FaqItem>> faqsAgrupados = {};
    for (var item in _faqsFiltrados) {
      if (!faqsAgrupados.containsKey(item.categoria)) {
        faqsAgrupados[item.categoria] = [];
      }
      faqsAgrupados[item.categoria]!.add(item);
    }

    return Scaffold(
      backgroundColor: const Color(0xFF1A2C42),
      appBar: AppBar(
        backgroundColor: const Color(0xFF101B2B),
        iconTheme: const IconThemeData(color: Colors.white),
        title: const Text(
          'Dúvidas Frequentes (FAQ)',
          style: TextStyle(color: Colors.white, fontWeight: FontWeight.bold),
        ),
      ),
      body: Column(
        children: [
          // BARRA DE PESQUISA
          Container(
            padding: const EdgeInsets.all(16.0),
            color: const Color(0xFF101B2B),
            child: TextField(
              controller: _searchController,
              style: const TextStyle(color: Colors.white),
              onChanged: (val) {
                setState(() {
                  _searchQuery = val.trim();
                });
              },
              decoration: InputDecoration(
                hintText: 'Digite sua dúvida ou palavra-chave...',
                hintStyle: const TextStyle(color: Colors.white54, fontSize: 14),
                prefixIcon: const Icon(Icons.search, color: Color(0xFFFF8C00)),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        icon: const Icon(Icons.clear, color: Colors.white54),
                        onPressed: () {
                          _searchController.clear();
                          setState(() {
                            _searchQuery = '';
                          });
                        },
                      )
                    : null,
                filled: true,
                fillColor: const Color(0xFF1A2C42),
                contentPadding: const EdgeInsets.symmetric(vertical: 14),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: BorderSide.none,
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Colors.white12),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(10),
                  borderSide: const BorderSide(color: Color(0xFFFF8C00)),
                ),
              ),
            ),
          ),

          // LISTA DE PERGUNTAS
          Expanded(
            child: _faqsFiltrados.isEmpty
                ? const Center(
                    child: Padding(
                      padding: EdgeInsets.all(24.0),
                      child: Text(
                        'Nenhuma dúvida encontrada com este termo.',
                        style: TextStyle(color: Colors.white54, fontSize: 15),
                        textAlign: TextAlign.center,
                      ),
                    ),
                  )
                : ListView.builder(
                    padding: const EdgeInsets.all(16.0),
                    itemCount: faqsAgrupados.keys.length,
                    itemBuilder: (context, index) {
                      final categoria = faqsAgrupados.keys.elementAt(index);
                      final itensDaCategoria = faqsAgrupados[categoria]!;

                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          // TÍTULO DA CATEGORIA
                          Padding(
                            padding: const EdgeInsets.only(
                                top: 12.0, bottom: 8.0, left: 4.0),
                            child: Text(
                              categoria,
                              style: const TextStyle(
                                color: Color(0xFFFF8C00),
                                fontSize: 16,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ),
                          // CARDS DE EXPANSÃO (SANFORNA / ACCORDION)
                          ...itensDaCategoria.map((faq) {
                            return Container(
                              margin: const EdgeInsets.only(bottom: 10),
                              decoration: BoxDecoration(
                                color: const Color(0xFF101B2B),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(color: Colors.white12),
                              ),
                              child: Theme(
                                data: Theme.of(context).copyWith(
                                  dividerColor: Colors.transparent,
                                ),
                                child: ExpansionTile(
                                  collapsedIconColor: const Color(0xFFFF8C00),
                                  iconColor: const Color(0xFFFF8C00),
                                  title: Text(
                                    faq.pergunta,
                                    style: const TextStyle(
                                      color: Colors.white,
                                      fontWeight: FontWeight.w600,
                                      fontSize: 14,
                                    ),
                                  ),
                                  children: [
                                    Container(
                                      width: double.infinity,
                                      padding: const EdgeInsets.all(16.0),
                                      decoration: const BoxDecoration(
                                        color: Color(0xFF1A2C42),
                                        borderRadius: BorderRadius.only(
                                          bottomLeft: Radius.circular(10),
                                          bottomRight: Radius.circular(10),
                                        ),
                                      ),
                                      child: Text(
                                        faq.resposta,
                                        style: const TextStyle(
                                          color: Colors.white70,
                                          fontSize: 13,
                                          height: 1.4,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          }).toList(),
                        ],
                      );
                    },
                  ),
          ),
        ],
      ),
    );
  }
}
