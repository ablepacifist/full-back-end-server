package gateway;

import org.springframework.beans.factory.annotation.Value;
import org.springframework.http.HttpHeaders;
import org.springframework.http.ResponseEntity;
import org.springframework.web.bind.annotation.*;
import org.springframework.web.reactive.function.client.WebClient;
import reactor.core.publisher.Mono;

import jakarta.servlet.http.HttpServletRequest;
import java.util.Collections;

/**
 * Simple gateway controller that proxies requests to backend services
 */
@RestController
@CrossOrigin(origins = "*")
public class GatewayController {
    
    @Value("${alchemy.service.url}")
    private String alchemyServiceUrl;
    
    @Value("${lexicon.service.url}")
    private String lexiconServiceUrl;
    
    private final WebClient webClient = WebClient.create();
    
    /**
     * Proxy all requests to alchemy service
     */
    @RequestMapping(value = "/api/alchemy/**", method = {RequestMethod.GET, RequestMethod.POST, RequestMethod.PUT, RequestMethod.DELETE})
    public Mono<ResponseEntity<String>> proxyToAlchemy(HttpServletRequest request, @RequestBody(required = false) String body) {
        String path = request.getRequestURI().substring("/api/alchemy".length());
        String queryString = request.getQueryString();
        String url = alchemyServiceUrl + "/api" + path + (queryString != null ? "?" + queryString : "");
        
        return webClient
                .method(org.springframework.http.HttpMethod.valueOf(request.getMethod()))
                .uri(url)
                .headers(headers -> {
                    // Copy important headers
                    String contentType = request.getHeader("Content-Type");
                    if (contentType != null) {
                        headers.set(HttpHeaders.CONTENT_TYPE, contentType);
                    }
                })
                .bodyValue(body != null ? body : "")
                .retrieve()
                .toEntity(String.class);
    }
    
    /**
     * Proxy all requests to lexicon service
     */
    @RequestMapping(value = "/api/lexicon/**", method = {RequestMethod.GET, RequestMethod.POST, RequestMethod.PUT, RequestMethod.DELETE})
    public Mono<ResponseEntity<String>> proxyToLexicon(HttpServletRequest request, @RequestBody(required = false) String body) {
        String path = request.getRequestURI().substring("/api/lexicon".length());
        String queryString = request.getQueryString();
        String url = lexiconServiceUrl + "/api" + path + (queryString != null ? "?" + queryString : "");
        
        return webClient
                .method(org.springframework.http.HttpMethod.valueOf(request.getMethod()))
                .uri(url)
                .headers(headers -> {
                    // Copy important headers
                    String contentType = request.getHeader("Content-Type");
                    if (contentType != null) {
                        headers.set(HttpHeaders.CONTENT_TYPE, contentType);
                    }
                })
                .bodyValue(body != null ? body : "")
                .retrieve()
                .toEntity(String.class);
    }
    
    /**
     * Health check endpoint
     */
    @GetMapping("/api/gateway/health")
    public ResponseEntity<?> health() {
        return ResponseEntity.ok().body("{\"status\":\"Gateway is running\",\"alchemy\":\"" + alchemyServiceUrl + "\",\"lexicon\":\"" + lexiconServiceUrl + "\"}");
    }
}
