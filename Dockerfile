# Usando a imagem do Maven para compilar o aplicativo
FROM maven:3.8.3-openjdk-17 AS builder

# Definindo o diretório de trabalho no contêiner
WORKDIR /app

# Copiando o arquivo de definição de projeto e os arquivos de código-fonte
COPY pom.xml .
COPY src ./src

# Compilando o aplicativo e gerando o arquivo JAR
RUN mvn clean install -DskipTests=true

# Usando a imagem do Amazon Corretto para executar o aplicativo
FROM amazoncorretto:17-al2-native-jdk

WORKDIR /app

# Copie o JAR gerado a partir da etapa anterior para o contêiner
COPY --from=builder /app/target/apiprocessamento-0.0.1-SNAPSHOT.jar .
COPY --from=builder /app/target/*.properties .

# Expondo a porta que o aplicativo está ouvindo
EXPOSE 8080

# Comando para iniciar o aplicativo
CMD ["java", "-jar", "apiprocessamento-0.0.1-SNAPSHOT.jar"]