package com.fiapx.apiprocessamento.adapter.out.bucket;

import com.fiapx.apiprocessamento.port.out.S3ServicePort;
import lombok.RequiredArgsConstructor;
import lombok.extern.slf4j.Slf4j;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.stereotype.Component;
import software.amazon.awssdk.core.sync.ResponseTransformer;
import software.amazon.awssdk.services.s3.S3Client;
import software.amazon.awssdk.services.s3.model.GetObjectRequest;
import software.amazon.awssdk.services.s3.model.PutObjectRequest;
import software.amazon.awssdk.services.s3.presigner.S3Presigner;
import software.amazon.awssdk.services.s3.presigner.model.GetObjectPresignRequest;

import java.io.IOException;
import java.net.URL;
import java.time.Duration;

@Slf4j
@Component
@RequiredArgsConstructor
public class S3Service implements S3ServicePort {

    @Value("${cloud.aws.bucket.videos}")
    private String bucketVideos;

    @Value("${cloud.aws.bucket.zips}")
    private String bucketZips;

    private final S3Client s3Client;
    private final S3Presigner s3Presigner;

    @Override
    public byte[] buscarVideo(String chave) throws IOException {
        log.info("Buscando vídeo no S3: {}", chave);

        GetObjectRequest getObjectRequest = GetObjectRequest.builder()
                .bucket(bucketVideos)
                .key(chave)
                .build();

        var videoResultado = s3Client.getObject(getObjectRequest, ResponseTransformer.toBytes()).asByteArray();

        log.info("Busca concluída no S3: {}", chave);

        return videoResultado;
    }

    @Override
    public void salvarImagens(String chave, byte[] imagensZip) {
        log.info("Salvando imagens zip no S3: {}", chave);

        PutObjectRequest putObjectRequest = PutObjectRequest.builder()
                .bucket(bucketZips)
                .key(chave)
                .build();

        s3Client.putObject(putObjectRequest, software.amazon.awssdk.core.sync.RequestBody.fromBytes(imagensZip));

        log.info("Imagens zip salvas no S3: {}", chave);
    }

    @Override
    public String gerarUrlPreAssinada(String chave) {
        log.info("Gerando URL pré-assinada para o arquivo: {}", chave);

        GetObjectRequest getObjectRequest = GetObjectRequest.builder()
                .bucket(bucketZips)
                .key(chave)
                .build();

        GetObjectPresignRequest presignRequest = GetObjectPresignRequest.builder()
                .signatureDuration(Duration.ofMinutes(60))
                .getObjectRequest(getObjectRequest)
                .build();

        URL urlPreAssinada = s3Presigner.presignGetObject(presignRequest).url();

        log.info("URL pré-assinada gerada: {}", urlPreAssinada);
        return urlPreAssinada.toString();
    }
}