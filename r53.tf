resource "aws_route53_record" "frontend_domain" {
  zone_id = var.domain_r53_host_id
  name = "${var.frontend_domain}"
  type = "A"

  alias {
    name = "${aws_cloudfront_distribution.frontend_cf_distribution.domain_name}"
    zone_id = "${aws_cloudfront_distribution.frontend_cf_distribution.hosted_zone_id}"
    evaluate_target_health = false
  }
}
