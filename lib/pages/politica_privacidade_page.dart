import 'package:flutter/material.dart';

class PoliticaPrivacidadePage extends StatelessWidget {
  const PoliticaPrivacidadePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      backgroundColor: const Color(0xFF1A2C42),
      appBar: AppBar(
        title: const Text("Política de Privacidade"),
        backgroundColor: const Color(0xFF101B2B),
        foregroundColor: Colors.orange,
      ),
      body: SingleChildScrollView(
        padding: const EdgeInsets.all(25),
        child: Center(
          child: Container(
            constraints: const BoxConstraints(maxWidth: 800),
            padding: const EdgeInsets.all(30),
            decoration: BoxDecoration(
              color: const Color(0xFF101B2B),
              borderRadius: BorderRadius.circular(16),
              border: Border.all(color: Colors.white12),
            ),
            child: const Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  "Política de Privacidade - Ache Obra",
                  style: TextStyle(
                    color: Colors.orange,
                    fontSize: 22,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  "Última atualização: 17 de setembro de 2026",
                  style: TextStyle(
                    color: Colors.white54,
                    fontSize: 13,
                  ),
                ),
                SizedBox(height: 20),
                Text(
                  "A sua privacidade é fundamental para nós. Esta Política de Privacidade descreve como o aplicativo Ache Obra e seus serviços relacionados coletam, utilizam, armazenam e protegem informações pessoais dos usuários, em conformidade com a Lei Geral de Proteção de Dados Pessoais (LGPD - Lei nº 13.709/2018).",
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
                SizedBox(height: 25),
                Text(
                  "1. Informações que Coletamos",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  "O Ache Obra pode coletar informações fornecidas diretamente pelo usuário durante o cadastro, utilização e atualização do perfil, incluindo nome, e-mail, telefone/WhatsApp, CPF quando necessário, cidade, estado, categoria e perfil de uso, como Cliente, Profissional, Arquiteto ou Engenheiro.",
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
                SizedBox(height: 10),
                Text(
                  "Também poderão ser armazenadas informações inseridas voluntariamente pelo usuário em seu perfil ou durante a utilização dos recursos disponibilizados pelo aplicativo, incluindo informações profissionais, descrições, solicitações, publicações, imagens e outros conteúdos necessários ao funcionamento da plataforma.",
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
                SizedBox(height: 10),
                Text(
                  "Podemos ainda coletar informações técnicas necessárias ao funcionamento e à segurança do serviço, como identificadores da conta, informações de autenticação, identificadores do dispositivo, tokens utilizados para notificações e registros técnicos relacionados ao funcionamento do aplicativo.",
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
                SizedBox(height: 25),
                Text(
                  "2. Uso das Informações",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  "As informações coletadas são utilizadas para permitir o funcionamento do Ache Obra, criar e administrar contas de usuários, disponibilizar perfis, conectar clientes a profissionais e prestadores de serviços da construção civil, permitir a utilização dos recursos da plataforma e facilitar a comunicação entre os usuários.",
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
                SizedBox(height: 10),
                Text(
                  "Os dados também podem ser utilizados para autenticação, segurança da conta, prevenção de uso indevido, gerenciamento de planos e recursos contratados, atendimento ao usuário, envio de notificações relacionadas ao funcionamento do aplicativo e melhoria dos serviços oferecidos.",
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
                SizedBox(height: 25),
                Text(
                  "3. Serviços de Terceiros",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  "Para fornecer determinadas funcionalidades, o Ache Obra utiliza serviços tecnológicos de terceiros. Entre eles estão o Supabase, utilizado para autenticação, banco de dados e armazenamento de informações, e serviços do Firebase, do Google, utilizados para funcionalidades como o envio de notificações.",
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
                SizedBox(height: 10),
                Text(
                  "Esses prestadores podem processar informações estritamente necessárias para a execução dos respectivos serviços, de acordo com suas próprias políticas de privacidade e práticas de segurança.",
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
                SizedBox(height: 10),
                Text(
                  "O Ache Obra não vende nem aluga os dados pessoais dos usuários para terceiros e não compartilha dados pessoais para fins de publicidade ou marketing de terceiros.",
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
                SizedBox(height: 25),
                Text(
                  "4. Pagamentos e Planos",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  "O Ache Obra pode oferecer planos pagos, assinaturas e outros recursos opcionais. Quando uma compra é realizada por meio de uma loja de aplicativos ou de um provedor de pagamento autorizado, determinadas informações da transação são processadas pelo respectivo provedor.",
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
                SizedBox(height: 10),
                Text(
                  "O Ache Obra poderá receber e armazenar informações necessárias para identificar e validar a compra, como produto ou plano adquirido, identificadores da transação, situação do pagamento e período de validade, quando aplicável.",
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
                SizedBox(height: 25),
                Text(
                  "5. Segurança das Informações",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  "Adotamos medidas técnicas e administrativas destinadas a proteger as informações pessoais contra acessos não autorizados, perda, alteração, divulgação ou uso indevido.",
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
                SizedBox(height: 10),
                Text(
                  "Embora sejam adotadas medidas de segurança compatíveis com os serviços oferecidos, nenhum sistema eletrônico de armazenamento ou transmissão de informações pode garantir segurança absoluta.",
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
                SizedBox(height: 25),
                Text(
                  "6. Retenção dos Dados",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  "Os dados pessoais são mantidos pelo período necessário para disponibilizar os serviços do Ache Obra, manter a conta do usuário e cumprir as finalidades descritas nesta Política de Privacidade.",
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
                SizedBox(height: 10),
                Text(
                  "Após uma solicitação de exclusão, os dados vinculados à conta serão excluídos ou anonimizados, ressalvadas as informações cuja conservação seja necessária para cumprimento de obrigações legais ou regulatórias, prevenção de fraudes, segurança, resolução de disputas ou exercício regular de direitos.",
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
                SizedBox(height: 25),
                Text(
                  "7. Exclusão de Conta e Direitos do Usuário (LGPD)",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  "O usuário poderá solicitar, nos termos da legislação aplicável, acesso, correção, atualização ou exclusão de seus dados pessoais.",
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
                SizedBox(height: 10),
                Text(
                  "A exclusão da conta pode ser solicitada diretamente dentro do aplicativo Ache Obra, por meio da opção de exclusão de conta disponível nas configurações ou no perfil do usuário.",
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
                SizedBox(height: 10),
                Text(
                  "O usuário também poderá solicitar a exclusão da conta por meio do suporte, enviando uma solicitação para suporte@acheobra.com.br e informando o e-mail utilizado no cadastro para que a solicitação possa ser identificada e processada.",
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
                SizedBox(height: 10),
                Text(
                  "A exclusão da conta resultará na remoção ou anonimização dos dados pessoais associados ao usuário, observadas as hipóteses legais que permitam ou exijam a conservação de determinadas informações.",
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
                SizedBox(height: 25),
                Text(
                  "8. Responsabilidade do Usuário",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  "O usuário é responsável pelas informações e conteúdos que fornece ao utilizar o Ache Obra e deve evitar publicar dados pessoais sensíveis ou informações de terceiros sem autorização.",
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
                SizedBox(height: 25),
                Text(
                  "9. Alterações desta Política",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  "Esta Política de Privacidade poderá ser atualizada periodicamente para refletir alterações no aplicativo, nos serviços oferecidos ou na legislação aplicável. A versão atualizada será disponibilizada nos canais oficiais do Ache Obra.",
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
                SizedBox(height: 25),
                Text(
                  "10. Contato e Privacidade",
                  style: TextStyle(
                    color: Colors.white,
                    fontSize: 16,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 8),
                Text(
                  "Para dúvidas, solicitações relacionadas à privacidade, proteção de dados ou exclusão de conta, entre em contato pelo e-mail: suporte@acheobra.com.br",
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                    height: 1.5,
                  ),
                ),
                SizedBox(height: 25),
                Divider(color: Colors.white24),
                SizedBox(height: 15),
                Text(
                  "Ache Obra",
                  style: TextStyle(
                    color: Colors.orange,
                    fontSize: 15,
                    fontWeight: FontWeight.bold,
                  ),
                ),
                SizedBox(height: 5),
                Text(
                  "Contato: suporte@acheobra.com.br",
                  style: TextStyle(
                    color: Colors.white70,
                    fontSize: 14,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
