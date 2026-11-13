# Estimation des coûts

Tarifs publics AWS pour la région **us-east-1**, appliqués aux ressources
réellement déployées par l'environnement `dev`. Les montants mensuels
supposent 730 heures de fonctionnement continu.

## Ressources facturées

| Ressource | Quantité | Tarif unitaire | Coût horaire | Coût mensuel |
|---|---:|---|---:|---:|
| NAT Gateway (heure) | 2 | 0,045 $/h | 0,0900 $ | 65,70 $ |
| Application Load Balancer | 1 | 0,0225 $/h | 0,0225 $ | 16,43 $ |
| Instances EC2 `t3.micro` | 2 | 0,0104 $/h | 0,0208 $ | 15,18 $ |
| Adresses IPv4 publiques | 4 | 0,005 $/h | 0,0200 $ | 14,60 $ |
| RDS `db.t3.micro` PostgreSQL | 1 | 0,018 $/h | 0,0180 $ | 13,14 $ |
| Stockage RDS `gp3` | 20 Go | 0,115 $/Go/mois | 0,0032 $ | 2,30 $ |
| **Total** | | | **≈ 0,175 $/h** | **≈ 127 $/mois** |

S'ajoutent des coûts variables, négligeables à l'échelle de la démonstration :

| Poste | Tarif | Remarque |
|---|---|---|
| Traitement NAT Gateway | 0,045 $/Go | Quelques centaines de Mo au démarrage des instances |
| LCU de l'ALB | 0,008 $/LCU-h | Une seule LCU suffit au trafic de démonstration |
| Stockage S3 | 0,023 $/Go/mois | Quelques Mo |
| DynamoDB (verrou) | à la demande | Quelques dizaines de requêtes |
| SSM Parameter Store | gratuit | Paramètres standard |
| Sortie Internet | 0,09 $/Go au-delà de 100 Go/mois | Hors seuil |

## Ce que cela signifie pour le budget de 50 $

| Durée de fonctionnement | Coût approximatif |
|---|---:|
| 1 heure | 0,18 $ |
| 1 journée de travail (8 h) | 1,40 $ |
| 1 jour complet (24 h) | 4,19 $ |
| 1 semaine | 29,33 $ |

**Le crédit de 50 $ couvre environ 285 heures, soit une douzaine de jours de
fonctionnement continu.** La marge est confortable pour un projet qui n'a
besoin d'être en ligne que pendant les phases de développement et la
soutenance — à condition de détruire l'infrastructure entre les sessions.

## Où part l'argent

Deux postes représentent à eux seuls près des deux tiers de la facture :

- **NAT Gateways : 52 %.** C'est le poste dominant, et de loin.
- **Load Balancer : 13 %.**

Les instances EC2, que l'on imagine spontanément être le centre de coût, ne
pèsent que 12 %.

## Réduire la facture

| Levier | Économie | Contrepartie |
|---|---:|---|
| Détruire l'environnement entre les sessions | jusqu'à 100 % | `terraform apply` prend ~10 min à la remise en route |
| Une seule NAT Gateway au lieu de deux | 32,85 $/mois | Sa zone devient un point de défaillance unique pour le trafic sortant |
| Endpoints VPC au lieu de NAT pour S3 et SSM | ~30 $/mois | Ne couvre pas les dépôts de paquets APT et GitHub |
| `desired_capacity = 1` en `dev` | 7,59 $/mois | Perte de la haute disponibilité, donc du test de panne |

Le choix de **deux NAT Gateways est assumé** : une seule ferait de sa zone un
point de défaillance unique pour tout le trafic sortant des instances, ce qui
contredit l'objectif de haute disponibilité du cahier des charges. L'économie
de 33 $/mois ne justifie pas de dégrader l'architecture que le projet doit
démontrer.

**Le levier qui compte réellement est le premier.** `terraform destroy` entre
deux sessions de travail ramène le coût à quelques centimes de stockage S3, et
c'est d'ailleurs ce que demande la section 5 du cahier des charges.

## Différences entre environnements

| Paramètre | `dev` | `test` | `prod` |
|---|---|---|---|
| `desired_capacity` | 2 | 2 | 3 ou plus |
| `instance_type` | `t3.micro` | `t3.micro` | `t3.small` ou plus |
| `db_instance_class` | `db.t3.micro` | `db.t3.micro` | `db.t3.small` ou plus |
| `multi_az` | `false` | `false` | `true` |

Activer `multi_az` double le coût de l'instance RDS (de 13 $ à 26 $ par mois) :
une instance de secours est maintenue dans une seconde zone. C'est justifié en
production, inutile en développement.

## Vérifier la consommation réelle

Le budget AWS Academy se consulte dans le tableau de bord du Learner Lab. En
ligne de commande, l'inventaire des ressources facturables actuellement
déployées :

```bash
aws ec2 describe-instances \
  --filters "Name=instance-state-name,Values=running" \
  --query 'Reservations[].Instances[].{Id:InstanceId,Type:InstanceType}' --output table

aws ec2 describe-nat-gateways --filter "Name=state,Values=available" \
  --query 'NatGateways[].NatGatewayId' --output table

aws rds describe-db-instances \
  --query 'DBInstances[].{Id:DBInstanceIdentifier,Class:DBInstanceClass}' --output table

aws elbv2 describe-load-balancers --query 'LoadBalancers[].LoadBalancerName' --output table
```

> Les tarifs évoluent. Ceux retenus ici sont ceux de us-east-1 au moment de la
> rédaction ; ils servent d'ordre de grandeur, pas d'engagement contractuel.
