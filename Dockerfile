FROM pablommr/kubernetes-eks:1.4.0

COPY entrypoint.sh /entrypoint.sh

ENTRYPOINT ["/entrypoint.sh"]