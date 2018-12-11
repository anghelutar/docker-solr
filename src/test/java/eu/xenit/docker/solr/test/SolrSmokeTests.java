package eu.xenit.docker.solr.test;

import io.restassured.RestAssured;
import io.restassured.authentication.PreemptiveBasicAuthScheme;
import io.restassured.builder.RequestSpecBuilder;
import io.restassured.parsing.Parser;
import io.restassured.specification.RequestSpecification;
import org.junit.BeforeClass;
import org.junit.Test;

import static io.restassured.RestAssured.given;
import static io.restassured.http.ContentType.JSON;
import static java.lang.Thread.sleep;
import static org.hamcrest.Matchers.equalTo;
import static org.hamcrest.Matchers.equalToIgnoringCase;
import static org.hamcrest.Matchers.greaterThan;
import static org.junit.Assert.*;

public class SolrSmokeTests {
    static RequestSpecification spec;
    static RequestSpecification specSharded;
    static RequestSpecification specShardedSolr1;
    static RequestSpecification specShardedSolr2;

    @BeforeClass
    public static void setup() {

        String basePath = "/alfresco/s/";
        String basePathSolr = "solr/admin/cores";
        if("solr4".equals(System.getProperty("flavor")))
            basePathSolr = "solr4/admin/cores";
        String host = System.getProperty("alfresco.host");
        String hostSharded = System.getProperty("alfresco-sharded.host");
        String solr1 = System.getProperty("solr1-sharded.host");
        String solr2 = System.getProperty("solr2-sharded.host");
        int port = Integer.parseInt(System.getProperty("alfresco.tcp.8080"));
        int portSharded = ((hostSharded!=null)?Integer.parseInt(System.getProperty("alfresco-sharded.tcp.8080")):-1);
        int portShardedSolr1 = ((hostSharded!=null)?Integer.parseInt(System.getProperty("solr1-sharded.tcp.8080")):-1);
        int portShardedSolr2 = ((hostSharded!=null)?Integer.parseInt(System.getProperty("solr2-sharded.tcp.8080")):-1);

        String baseURI = "http://" + host;
        String baseURISharded = "http://" + hostSharded;
        String baseURIShardedSolr1 = "http://" + solr1;
        String baseURIShardedSolr2 = "http://" + solr2;

        PreemptiveBasicAuthScheme authScheme = new PreemptiveBasicAuthScheme();
        authScheme.setUserName("admin");
        authScheme.setPassword("admin");
        RestAssured.defaultParser = Parser.JSON;

        spec = new RequestSpecBuilder()
                .setBaseUri(baseURI)
                .setPort(port)
                .setBasePath(basePath)
                .setAuth(authScheme)
                .build();
        if(hostSharded != null) {
            specSharded = new RequestSpecBuilder()
                    .setBaseUri(baseURISharded)
                    .setPort(portSharded)
                    .setBasePath(basePath)
                    .setAuth(authScheme)
                    .build();
            specShardedSolr1 = new RequestSpecBuilder()
                    .setBaseUri(baseURIShardedSolr1)
                    .setPort(portShardedSolr1)
                    .setBasePath(basePathSolr)
                    .addParam("action","STATUS")
                    .addParam("wt","json")
                    .build();
            specShardedSolr2 = new RequestSpecBuilder()
                    .setBaseUri(baseURIShardedSolr2)
                    .setPort(portShardedSolr2)
                    .setBasePath(basePathSolr)
                    .addParam("action","STATUS")
                    .addParam("wt","json")
                    .build();
        } else {
            specSharded = null;
            specShardedSolr1 = null;
            specShardedSolr2 = null;
        }
    }


    @Test
    // Note: due to eventual consistency, we can't test the expected number of results
    public void testSearch(){
        given()
                .spec(spec)
                .when()
                .get("slingshot/search?term=test*")
                .then()
                .statusCode(200);
        if(specSharded!=null)
            given()
                    .spec(specSharded)
                    .when()
                    .get("slingshot/search?term=test*")
                    .then()
                    .statusCode(200);
    }

    @Test
    public void TestShards() {
        if(specSharded!=null) {
            try {
                // wait for solr to track
                sleep(30000);
            } catch (InterruptedException e) {
                e.printStackTrace();
            }
        }
        if(specShardedSolr1!=null) {
            Integer docs0 = given()
                    .spec(specShardedSolr1)
                    .contentType("application/json")
                    .when()
                    .get()
                    .then()
                    .statusCode(200)
                    .contentType(JSON)
                    .extract().path("status.alfresco-0.index.numDocs");
            Integer docs1 = given()
                    .spec(specShardedSolr1)
                    .contentType("application/json")
                    .when()
                    .get()
                    .then()
                    .statusCode(200)
                    .contentType(JSON)
                    .extract().path("status.alfresco-1.index.numDocs");
            Integer docs2 = given()
                    .spec(specShardedSolr2)
                    .contentType("application/json")
                    .when()
                    .get()
                    .then()
                    .statusCode(200)
                    .contentType(JSON)
                    .extract().path("status.alfresco-2.index.numDocs");
            assertThat(docs0,greaterThan(50));
            assertThat(docs1,greaterThan(50));
            assertThat(docs2,greaterThan(50));
        }
    }
}
